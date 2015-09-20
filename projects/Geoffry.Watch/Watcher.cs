using System;
using System.Collections.Concurrent;
using System.Collections.Generic;

namespace Geoffry.Watch
{
    public static class Watcher
    {
        private static readonly ConcurrentDictionary<Guid, WatchEnvironment> Environments = new ConcurrentDictionary<Guid, WatchEnvironment>();

        public static event WatchEventHandler Changed;

        public static Guid Subscribe(TimeSpan granularity, IEnumerable<WatchDefinition> definitions)
        {
            Guid token = Guid.NewGuid();
            WatchEnvironment environment = new WatchEnvironment(token, granularity, definitions);
            Environments[token] = environment;
            environment.Changed += RelayChanged;
            environment.StartWatching();
            return token;
        }

        private static void OnChanged(Guid token)
        {
            WatchEventHandler handler = Changed;

            if (handler != null)
            {
                handler(null, new WatchEventArgs(token));
            }
        }

        private static void RelayChanged(object sender, WatchEventArgs e)
        {
            OnChanged(e.Token);
        }

        public static void Cancel(Guid token)
        {
            WatchEnvironment environment;
            Environments.TryRemove(token, out environment);
            environment?.StopWatching();
        }

        public static void CancelAll() {
            Environments.Clear();
        }

        public static ConcurrentDictionary<Guid, WatchEnvironment> GetWatchers {
            get {
                return Environments;
            }
        }
    }
}