using System;
using System.Text;
using Xunit;

namespace Opensms.Tests
{
    /// <summary>CONFORMANCE.md unit test 18: every row of the DESIGN.md signature table.</summary>
    public class WebhookSignatureTests
    {
        private const string Secret = "whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE";
        private const long T = 1790208000;
        private const string Body = "{\"id\":\"evt_01\",\"type\":\"message.delivered\",\"workspace_id\":\"00000000-0000-0000-0000-000000000001\",\"environment\":\"sandbox\",\"created_at\":\"2026-09-24T00:00:00Z\",\"data\":{\"id\":\"00000000-0000-0000-0000-000000000002\",\"status\":\"delivered\"}}";
        private const string Digest = "eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23";
        private const string Header = "t=1790208000,v1=" + Digest;

        private static DateTimeOffset At(long unix) => DateTimeOffset.FromUnixTimeSeconds(unix);

        [Fact]
        public void Body_is_230_bytes() => Assert.Equal(230, Encoding.UTF8.GetByteCount(Body));

        [Fact]
        public void Sign_reproduces_the_vector() => Assert.Equal(Header, WebhookSignature.Sign(Secret, Encoding.UTF8.GetBytes(Body), At(T)));

        [Theory]
        [InlineData(Header, 0, true)]                                   // header above
        [InlineData(Header, 300, true)]                                 // +300 inclusive boundary
        [InlineData(Header, 301, false)]                                // +301 expired
        [InlineData(Header, -301, false)]                               // -301 expired
        [InlineData("v1=" + Digest + ",t=1790208000", 0, true)]         // order swapped
        [InlineData(Header + ",v0=abc", 0, false)]                      // extra key
        [InlineData("t=1790208000", 0, false)]                          // t only
        [InlineData("t=1790208000,v1=EEB2EC420DD348B253DAE35C1F3BCE03D261109EB8788E3AD836072E894FAC23", 0, true)] // uppercase hex
        [InlineData(" t=1790208000 , v1=" + Digest + " ", 0, true)]     // parts are trimmed
        [InlineData("t=1790208000,t=1790208000,v1=" + Digest, 0, false)] // duplicate key
        [InlineData("t=abc,v1=" + Digest, 0, false)]                    // non-integer t
        [InlineData("t=1790208000,v1=" + "zz", 0, false)]               // short / non-hex digest
        [InlineData("", 0, false)]
        public void Vector_rows(string header, long offset, bool valid)
            => Assert.Equal(valid, WebhookSignature.Verify(Body, header, Secret, now: At(T + offset)));

        [Fact]
        public void Tampered_body_is_invalid()
            => Assert.False(WebhookSignature.Verify(Body.Replace("\"status\":\"delivered\"", "\"status\":\"failed\""), Header, Secret, now: At(T)));

        [Fact]
        public void Secret_without_prefix_is_invalid()
            => Assert.False(WebhookSignature.Verify(Body, Header, Secret.Substring("whsec_".Length), now: At(T)));

        [Fact]
        public void Empty_secret_is_invalid()
        {
            Assert.False(WebhookSignature.Verify(Body, Header, "", now: At(T)));
            Assert.False(WebhookSignature.Verify(Body, Header, null, now: At(T)));
        }

        [Fact]
        public void Bytes_overload_matches()
            => Assert.True(WebhookSignature.Verify(Encoding.UTF8.GetBytes(Body), Header, Secret, now: At(T)));

        [Fact]
        public void Custom_tolerance()
        {
            Assert.False(WebhookSignature.Verify(Body, Header, Secret, TimeSpan.FromSeconds(10), At(T + 11)));
            Assert.True(WebhookSignature.Verify(Body, Header, Secret, TimeSpan.FromSeconds(10), At(T + 10)));
        }

        [Fact]
        public void ConstructEvent_valid_row_parses_the_envelope()
        {
            var evt = WebhookSignature.ConstructEvent(Body, Header, Secret, now: At(T));
            Assert.Equal("evt_01", evt.Id);
            Assert.Equal("message.delivered", evt.Type);
            Assert.Equal("sandbox", evt.Environment);
            Assert.Equal("delivered", evt.Data!.Value.GetProperty("status").GetString());
        }

        [Fact]
        public void ConstructEvent_tampered_row_is_invalid_signature()
        {
            var ex = Assert.Throws<OpensmsException>(() => WebhookSignature.ConstructEvent(Body.Replace("\"delivered\"}", "\"failed\"}"), Header, Secret, now: At(T)));
            Assert.Equal(0, ex.Status);
            Assert.Equal("invalid_signature", ex.Code);
        }

        [Fact]
        public void ConstructEvent_expired_row_is_expired_signature()
        {
            var ex = Assert.Throws<OpensmsException>(() => WebhookSignature.ConstructEvent(Body, Header, Secret, now: At(T + 301)));
            Assert.Equal(0, ex.Status);
            Assert.Equal("expired_signature", ex.Code);
        }

        [Fact]
        public void Client_exposes_the_same_helpers()
        {
            using var client = new OpensmsClient(Fx.TestKey);
            Assert.True(client.Webhooks.VerifySignature(Body, Header, Secret, now: At(T)));
            Assert.Equal("message.delivered", client.Webhooks.ConstructEvent(Body, Header, Secret, now: At(T)).Type);
        }
    }
}
