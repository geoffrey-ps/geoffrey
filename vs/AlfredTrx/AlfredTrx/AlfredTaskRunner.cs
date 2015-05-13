using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Media;
using Microsoft.VisualStudio.TaskRunnerExplorer;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.IO;
using System.Drawing;
using System.Linq;
using System.Collections;
using System.Net;

namespace AlfredTrx
{
    public static class Alfred
    {
        private static Task<bool> _initTask;
        private static PowerShell _ps;

        public static string ModulePath { get; private set; }

        private static async Task InstallAlfredAsync()
        {
            HttpWebRequest request = WebRequest.CreateHttp("https://raw.githubusercontent.com/sayedihashimi/alfredps/master/getalfred.ps1");
            request.UserAgent = "AlfredTRX-VS" + typeof(ITaskRunner).Assembly.GetName().Version;
            WebResponse response = await request.GetResponseAsync();
            Stream responseStream = response.GetResponseStream();
            string alfredSource;

            using (StreamReader reader = new StreamReader(responseStream))
            {
                alfredSource = await reader.ReadToEndAsync();
            }

            _ps.AddScript(alfredSource);
            _ps.Invoke();
        }

        public static async Task EnsureInitialized(ITaskRunnerCommandContext context)
        {
            TaskCompletionSource<bool> tcs = new TaskCompletionSource<bool>();
            Task existing = Interlocked.CompareExchange(ref _initTask, tcs.Task, null);

            //If we own the initialization...
            if(existing == null)
            {
                _ps = PowerShell.Create();

                _ps.Streams.Error.DataAdded += (sender, args) =>
                {
                    foreach (ErrorRecord record in _ps.Streams.Error.ReadAll())
                    {
                        string message = record?.ErrorDetails?.Message;

                        if (message != null)
                        {
                            context.CommandStatus.Errors.Add(message);
                        }
                    }
                };

                _ps.Streams.Verbose.DataAdded += (sender, args) =>
                {
                    foreach (VerboseRecord record in _ps.Streams.Verbose.ReadAll())
                    {
                        string message = record?.Message;

                        if (message != null)
                        {
                            context.CommandStatus.Messages.Add(message);
                        }
                    }
                };

                _ps.Streams.Warning.DataAdded += (sender, args) =>
                {
                    foreach (WarningRecord record in _ps.Streams.Warning.ReadAll())
                    {
                        string message = record?.Message;

                        if (message != null)
                        {
                            context.CommandStatus.Warnings.Add(message);
                        }
                    }
                };

                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                ModulePath = Path.Combine(localAppData, "Ligershark\\tools\\alfredps-pre\\alfred.psm1");

                //If we don't already have alfred installed, install it
                if (!File.Exists(ModulePath))
                {
                    await InstallAlfredAsync();
                }

                _ps.Commands.Clear();
                Command importModule = new Command("Import-Module");
                importModule.Parameters.Add("Name", ModulePath);
                _ps.Commands.AddCommand(importModule);
                _ps.Invoke();
                
                tcs.SetResult(true);
                return;
            }

            await existing;
        }

        internal static IEnumerable<string> DiscoverTasksIn(string configPath)
        {
            _ps.Commands.Clear();
            Command listCommand = new Command("alfred");
            listCommand.Parameters.Add("scriptPath", configPath);
            listCommand.Parameters.Add("list");
            _ps.Commands.AddCommand(listCommand);
            IEnumerable<PSObject> result = _ps.Invoke();
            dynamic names = (dynamic)_ps.Runspace.SessionStateProxy.GetVariable("alfredcontext");
            IEnumerable<string> taskNames = ((IEnumerable)names.Tasks.Keys).OfType<string>();
            return taskNames.Select(x => x.Trim()).OrderBy(x => x);
        }
    }

	/// <summary>
	/// Task runner for AlfredPS
	/// </summary>
	[TaskRunnerExport("alfred.ps1")]
	public class AlfredTaskRunner : ITaskRunner
	{
        private static List<ITaskRunnerOption> _options = new List<ITaskRunnerOption>();

        /// <summary>
        /// Parses a configuration file into ITaskRunnerConfig
        /// </summary>
        /// <param name="configPath"></param>
        /// <param name="taskRunnerOptions"></param>
        /// <param name="environmentPath"></param>
        /// <param name="projectItem"></param>
        /// <returns></returns>
		public async Task<ITaskRunnerConfig> ParseConfig(ITaskRunnerCommandContext context, string configPath)
		{
            await Alfred.EnsureInitialized(context);
            ITaskRunnerNode hierarchy = LoadHierarchy(configPath);
            return new AlfredTaskRunnerConfig(context, hierarchy);
		}

        private ITaskRunnerNode LoadHierarchy(string configPath)
        {
            ITaskRunnerNode root = new TaskRunnerNode("Alfred");
            string workingDirectory = Path.GetDirectoryName(configPath);

            foreach (string taskName in Alfred.DiscoverTasksIn(configPath))
            {
                string args = @"-Command ""Import-Module '" + Alfred.ModulePath + "' 3>$null; alfred -scriptPath '" + configPath + "' -taskName " + taskName + @"""";

                ITaskRunnerNode task = new TaskRunnerNode(taskName, true)
                {
                    Command = new TaskRunnerCommand(workingDirectory, "powershell.exe", args)
                };

                root.Children.Add(task);
            }

            return root;
        }


        /// <summary>
        /// List of task runner command line possible options
        /// </summary>
        public List<ITaskRunnerOption> Options => _options;
	}
	
	/// <summary>
	/// Configuration for an AlfredPS task
	/// </summary>
	public class AlfredTaskRunnerConfig : ITaskRunnerConfig
	{
		private static readonly ImageSource SharedIcon = LoadSharedIcon();
        private ITaskRunnerCommandContext _context;

        public AlfredTaskRunnerConfig(ITaskRunnerCommandContext context, ITaskRunnerNode hierarchy)
        {
            TaskHierarchy = hierarchy;
            _context = context;
        }

		private static ImageSource LoadSharedIcon()
		{
            return null;
		} 
		
        /// <summary>
        /// TaskRunner icon 
        /// </summary>
        public ImageSource Icon => SharedIcon;
        
        /// <summary>
        /// ITaskRunnerNode tree that represents the task runner nodes hierarchy
        /// </summary>                  
		public ITaskRunnerNode TaskHierarchy { get; }

        /// <summary>
        /// Reads a configuration path and returns the XML string in a specified format 
        ///  that can be understood by Task Runner Explorer  
        /// </summary>
        /// <param name="configPath"></param>
        /// <returns></returns>
        public string LoadBindings(string configPath)
        {
            string config = configPath + ".trxcfg";

            if (!File.Exists(config))
            {
                return null;
            }

            return File.ReadAllText(configPath + ".trxcfg");
        }

        /// <summary>
        ///  Saves the bindings XML data back to configuration file or any other 
        ///   sources.
        /// </summary>
        /// <param name="configPath"></param>
        /// <param name="bindingsXml"></param>
        /// <returns></returns>
		public bool SaveBindings(string configPath, string bindingsXml)
		{
            File.WriteAllText(configPath + ".trxcfg", bindingsXml);
            return true;
		}

        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool isDisposing)
        {

        }
	}	
}