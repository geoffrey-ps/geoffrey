using System;

namespace Geoffry.Watch
{
    public class WatchEventArgs : EventArgs
    {
        public WatchEventArgs(Guid token)
        {
            Token = token;
        }

        public Guid Token { get; }
    }
}