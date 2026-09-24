using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace Opensms
{
    /// <summary>Common <c>limit</c> + <c>cursor</c> parameters for cursor-paged lists.</summary>
    public class ListParams
    {
        /// <summary>Page size (messages 1..100, other lists 1..200).</summary>
        public int? Limit { get; set; }

        /// <summary>The <c>next_cursor</c> from the previous page.</summary>
        public string? Cursor { get; set; }

        /// <summary>A shallow copy with a different cursor (used by the pagination helper).</summary>
        internal ListParams WithCursor(string? cursor)
        {
            var copy = (ListParams)MemberwiseClone();
            copy.Cursor = cursor;
            return copy;
        }
    }

    /// <summary>One page of a cursor-paged list.</summary>
    public sealed class Page<T>
    {
        /// <summary>The items on this page.</summary>
        [JsonPropertyName("items")] public List<T> Items { get; set; } = new List<T>();

        /// <summary>Pass back as <c>Cursor</c> for the next page; <c>null</c> on the last page.</summary>
        [JsonPropertyName("next_cursor")] public string? NextCursor { get; set; }
    }

    /// <summary>The auto-pagination helper behind <see cref="OpensmsClient.PaginateAsync{TParams, T}"/>.</summary>
    public static class Paginator
    {
        /// <summary>
        /// Call <paramref name="list"/> repeatedly, feeding <c>NextCursor</c> back as
        /// <c>Cursor</c> until it is null, yielding items lazily. The caller's
        /// params object is never mutated.
        /// </summary>
        public static async IAsyncEnumerable<T> PaginateAsync<TParams, T>(
            Func<TParams?, CancellationToken, Task<Page<T>>> list,
            TParams? parameters = null,
            [EnumeratorCancellation] CancellationToken ct = default)
            where TParams : ListParams, new()
        {
            if (list == null) throw new ArgumentNullException(nameof(list));
            var current = parameters ?? new TParams();
            while (true)
            {
                var page = await list(current, ct).ConfigureAwait(false);
                foreach (var item in page.Items) yield return item;
                if (string.IsNullOrEmpty(page.NextCursor)) yield break;
                current = (TParams)current.WithCursor(page.NextCursor);
            }
        }
    }
}
