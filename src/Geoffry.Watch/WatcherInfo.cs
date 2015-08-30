using System;
using System.Collections.Generic;
using System.Linq;
using Minimatch;

namespace Geoffry.Watch
{
    public class WatcherInfo
    {
        public Uri RootDirectory { get; private set; }

        public IReadOnlyList<Minimatcher> Patterns { get; private set; }

        public WatcherInfo(string rootDirectory, IEnumerable<string> patterns)
        {
            RootDirectory = new Uri(rootDirectory, UriKind.Absolute);
            Patterns = patterns.Select(x => new Minimatcher(x, new Options {AllowWindowsPaths = true, IgnoreCase = true})).ToList();
        }
    }
}