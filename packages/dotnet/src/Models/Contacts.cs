using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Opensms
{
    /// <summary>An address-book contact.</summary>
    public sealed class Contact
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("workspace_id")] public string? WorkspaceId { get; set; }
        [JsonPropertyName("e164")] public string? E164 { get; set; }
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("attributes")] public Dictionary<string, JsonElement>? Attributes { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
    }

    /// <summary>Parameters for <see cref="ContactsResource.CreateAsync"/>.</summary>
    public sealed class CreateContactParams
    {
        [JsonPropertyName("e164")] public required string E164 { get; set; }
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("attributes")] public IDictionary<string, object?>? Attributes { get; set; }
    }

    /// <summary>Partial update for <see cref="ContactsResource.UpdateAsync"/>; unset fields are left unchanged.</summary>
    public sealed class UpdateContactParams
    {
        [JsonPropertyName("e164")] public string? E164 { get; set; }
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("attributes")] public IDictionary<string, object?>? Attributes { get; set; }
    }

    /// <summary>A named set of contacts.</summary>
    public sealed class ContactGroup
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("workspace_id")] public string? WorkspaceId { get; set; }
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("contact_ids")] public List<string>? ContactIds { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
    }

    /// <summary>Parameters for <see cref="ContactGroupsResource.CreateAsync"/>.</summary>
    public sealed class CreateContactGroupParams
    {
        [JsonPropertyName("name")] public required string Name { get; set; }
        [JsonPropertyName("contact_ids")] public IList<string>? ContactIds { get; set; }
    }

    /// <summary>Partial update for <see cref="ContactGroupsResource.UpdateAsync"/>.</summary>
    public sealed class UpdateContactGroupParams
    {
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("contact_ids")] public IList<string>? ContactIds { get; set; }
    }

    /// <summary>Parameters for <see cref="ContactGroupsResource.SendAsync"/>: set exactly one of <see cref="Text"/> or <see cref="TemplateId"/>.</summary>
    public sealed class GroupSendParams
    {
        [JsonPropertyName("text")] public string? Text { get; set; }
        [JsonPropertyName("template_id")] public string? TemplateId { get; set; }
        [JsonPropertyName("variables")] public IDictionary<string, string>? Variables { get; set; }
        [JsonPropertyName("sender_id")] public string? SenderId { get; set; }
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
        [JsonPropertyName("callback_url")] public string? CallbackUrl { get; set; }
    }

    /// <summary>A reusable message template.</summary>
    public sealed class Template
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("workspace_id")] public string? WorkspaceId { get; set; }
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("body")] public string? Body { get; set; }
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
        [JsonPropertyName("updated_at")] public DateTimeOffset? UpdatedAt { get; set; }
        /// <summary>The <c>{{name}}</c> placeholders parsed from the body.</summary>
        [JsonPropertyName("variables")] public List<string>? Variables { get; set; }
    }

    /// <summary>Parameters for <see cref="TemplatesResource.CreateAsync"/>.</summary>
    public sealed class CreateTemplateParams
    {
        [JsonPropertyName("name")] public required string Name { get; set; }
        [JsonPropertyName("body")] public required string Body { get; set; }
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
    }

    /// <summary>Partial update for <see cref="TemplatesResource.UpdateAsync"/>.</summary>
    public sealed class UpdateTemplateParams
    {
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("body")] public string? Body { get; set; }
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
    }
}
