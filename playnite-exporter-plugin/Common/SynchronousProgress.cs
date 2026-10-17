using System;

namespace PlayniteExporterPlugin.Common
{
    /// <summary>
    /// Synchronous, thread-safe implementation of IProgress&lt;T&gt;.
    /// Directly invokes the callback on the reporting thread without capturing
    /// SynchronizationContext or hopping through thread pool / WPF Dispatcher.
    /// This avoids deadlocks when updating thread-safe properties in Playnite's GlobalProgressActionArgs.
    /// </summary>
    public class SynchronousProgress<T> : IProgress<T>
    {
        private readonly Action<T> handler;

        public SynchronousProgress(Action<T> handler)
        {
            this.handler = handler ?? throw new ArgumentNullException(nameof(handler));
        }

        public void Report(T value)
        {
            handler(value);
        }
    }
}
