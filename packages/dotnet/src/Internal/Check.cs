using System;

namespace Opensms.Internal
{
    /// <summary>Argument guards: fail locally, before any request.</summary>
    internal static class Check
    {
        public static T NotNull<T>(T? value, string name) where T : class
            => value ?? throw new ArgumentNullException(name);
    }
}
