using System;
using Geoffry.Watch;

namespace GeoffreySampleConsoleApp
{
    class Program
    {
        static void Main()
        {
            Watcher.Changed += OnChanged;

            Guid token = Watcher.Subscribe(TimeSpan.FromMilliseconds(500), new[]
            {
                new WatchDefinition
                {
                    GlobbingPattern = "**/*.json",
                    RootDirectory = @"c:\Example\json"
                },
                new WatchDefinition
                {
                    GlobbingPattern = "**/*.css",
                    RootDirectory = @"c:\Example\css"
                }
            });

            Console.ReadLine();
            Watcher.Cancel(token);
        }

        private static void OnChanged(object sender, WatchEventArgs e)
        {
            Console.WriteLine(e.Token);
        }
    }
}
