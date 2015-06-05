using Microsoft.VisualStudio.TaskRunnerExplorer;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace AlfredTrx.Helpers
{
    public class TaskRunnerOption : ITaskRunnerOption
    {
        public TaskRunnerOption(string optionName, uint commandId, Guid commandGroup, bool isEnabled, string command)
        {
            Command = command;
            Id = commandId;
            Guid = commandGroup;
            Name = optionName;
#if RC
            Enabled = isEnabled;
#else
            Checked = isEnabled;
#endif
        }

        public string Command { get; set; }

#if RC
        public bool Enabled { get; set; }
#else
        public bool Checked { get; set; }
#endif

        public Guid Guid { get; }

        public uint Id { get; }

        public string Name { get; }
    }
}
