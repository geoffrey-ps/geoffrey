using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using GeoffreyTrx.Helpers;
using Microsoft.VisualStudio.TaskRunnerExplorer;

namespace GeoffreyTrx
{
    /// <summary>
    /// Task runner for Geoffrey
    /// </summary>
    [TaskRunnerExport("g.ps1")]
	public class GeoffreyTaskRunner : ITaskRunner
	{
        private static List<ITaskRunnerOption> _options;

        /// <summary>
        /// List of task runner command line possible options
        /// </summary>
        public List<ITaskRunnerOption> Options => _options;

        private ImageSource _icon;

        public GeoffreyTaskRunner()
        {
            _icon = new BitmapImage(new Uri(@"pack://application:,,,/GeoffreyTRX;component/Resources/GeoffreyLogo-31x31.png"));
            _options = new List<ITaskRunnerOption>();
            _options.Add(new TaskRunnerOption("Verbose", PkgCmdIDList.cmdidVerboseTaskRunners, GuidList.guidTaskRunnerExplorerExtensionsCmdSet, false, "-verbose"));
        }


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
            //Custom
            await Geoffrey.EnsureInitialized(context);
            ITaskRunnerNode hierarchy = LoadHierarchy(configPath);

            //Common
            return new TaskRunnerConfig<PowershellBindingsPersister>(context, hierarchy, _icon);
		}

        private ITaskRunnerNode LoadHierarchy(string configPath)
        {
            //Custom
            ITaskRunnerNode root = new TaskRunnerNode("Geoffrey");
            string workingDirectory = Path.GetDirectoryName(configPath);
            
            foreach (string taskName in Geoffrey.DiscoverTasksIn(configPath))
            {
                string args = @"-NoProfile -NoLogo -NonInteractive -ExecutionPolicy RemoteSigned -Command ""Import-Module '" + Geoffrey.ModulePath + "' 3>$null; Invoke-Geoffrey -scriptPath '" + configPath + "' -taskName " + taskName + @"""";

                ITaskRunnerNode task = new TaskRunnerNode(taskName, true)
                {
                    Command = new TaskRunnerCommand(workingDirectory, "powershell.exe", args)
                };

                root.Children.Add(task);
            }

            return root;
        }
	}
}