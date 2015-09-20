using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace Geoffry.Watch
{
    public class WatchEnvironment
    {
        private readonly TimeSpan _granularity;
        private readonly IReadOnlyDictionary<FileSystemWatcher, WatcherInfo> _patternsByWatcher;
        private readonly object _timerSync = new object();
        private readonly Guid _token;
        private Timer _timer;

        public WatchEnvironment(Guid token, TimeSpan granularity, IEnumerable<WatchDefinition> definitions)
        {
            _token = token;
            _granularity = granularity;
            Dictionary<FileSystemWatcher, WatcherInfo> patternsByWatcher = new Dictionary<FileSystemWatcher, WatcherInfo>();

            foreach (IGrouping<string, string> grouping in definitions.GroupBy(x => x?.RootDirectory?.TrimEnd('/', '\\'), x => x?.GlobbingPattern, StringComparer.OrdinalIgnoreCase))
            {
                FileSystemWatcher watcher = new FileSystemWatcher(grouping.Key) {IncludeSubdirectories = true};
                watcher.Changed += HandleChanged;
                watcher.Created += HandleCreated;
                watcher.Deleted += HandleDeleted;
                watcher.Renamed += HandleRenamed;
                patternsByWatcher[watcher] = new WatcherInfo(grouping.Key, grouping);
            }

            _patternsByWatcher = patternsByWatcher;
        }

        public event WatchEventHandler Changed;

        public void StartWatching()
        {
            foreach (FileSystemWatcher watcher in _patternsByWatcher.Keys)
            {
                watcher.EnableRaisingEvents = true;
            }
        }

        public void StopWatching()
        {
            foreach (FileSystemWatcher watcher in _patternsByWatcher.Keys)
            {
                watcher.EnableRaisingEvents = false;
            }
        }

        private void DemandTimer()
        {
            if (_timer == null)
            {
                lock (_timerSync)
                {
                    Timer newTimer = new Timer(OnTick, null, TimeSpan.Zero, TimeSpan.FromMilliseconds(-1));
                    Interlocked.CompareExchange(ref _timer, newTimer, null);
                }
            }
        }

        private void HandleChange(FileSystemWatcher watcher, string file)
        {
            WatcherInfo info = _patternsByWatcher[watcher];
            Uri fileUri = new Uri(file, UriKind.Absolute);
            Uri rel = info.RootDirectory.MakeRelativeUri(fileUri);

            if (info.Patterns.Any(x => x.IsMatch(rel.ToString())))
            {
                DemandTimer();
                _timer.Change(_granularity, TimeSpan.FromMilliseconds(-1));
            }
        }

        private void HandleChanged(object sender, FileSystemEventArgs e)
        {
            HandleChange((FileSystemWatcher)sender, e.FullPath);
        }

        private void HandleCreated(object sender, FileSystemEventArgs e)
        {
            HandleChange((FileSystemWatcher)sender, e.FullPath);
        }

        private void HandleDeleted(object sender, FileSystemEventArgs e)
        {
            HandleChange((FileSystemWatcher)sender, e.FullPath);
        }

        private void HandleRenamed(object sender, RenamedEventArgs e)
        {
            HandleChange((FileSystemWatcher)sender, e.FullPath);
        }

        private void OnTick(object state)
        {
            WatchEventHandler handler = Changed;

            if (handler != null)
            {
                handler(this, new WatchEventArgs(_token));
            }
        }
    }
}