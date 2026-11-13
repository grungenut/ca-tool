// C/A Tool launcher: a small Windows program that runs CATool.ps1, which is
// embedded inside it, using the PowerShell engine built into Windows.
// Built by build.ps1 with the C# compiler that ships with .NET Framework 4.
// Keep this to C# 5 syntax (that compiler is old).

using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows.Forms;

[assembly: AssemblyTitle("C/A Tool")]
[assembly: AssemblyProduct("C/A Tool")]
[assembly: AssemblyDescription("On-screen overlay for measuring condylar and axial circles")]
[assembly: AssemblyVersion("{VERSION}")]
[assembly: AssemblyFileVersion("{VERSION}")]

namespace CATool
{
    static class Program
    {
        [STAThread]
        static int Main()
        {
            try
            {
                string script;
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("CATool.ps1"))
                using (StreamReader r = new StreamReader(s))
                {
                    script = r.ReadToEnd();
                }

                InitialSessionState iss = InitialSessionState.CreateDefault();
                iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
                iss.ApartmentState = ApartmentState.STA;           // WPF windows need STA
                iss.ThreadOptions = PSThreadOptions.UseCurrentThread;

                using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
                {
                    rs.Open();
                    using (PowerShell ps = PowerShell.Create())
                    {
                        ps.Runspace = rs;
                        ps.AddScript(script);
                        ps.Invoke();
                        // Startup failures are shown by the script itself; anything else is logged.
                        foreach (ErrorRecord e in ps.Streams.Error) { Log(e.ToString()); }
                    }
                }
                return 0;
            }
            catch (Exception ex)
            {
                Log(ex.ToString());
                MessageBox.Show("C/A Tool could not start:\n\n" + ex.Message, "C/A Tool");
                return 1;
            }
        }

        static void Log(string message)
        {
            try
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CATool");
                Directory.CreateDirectory(dir);
                File.AppendAllText(Path.Combine(dir, "error.log"),
                    DateTime.Now.ToString("s") + "  " + message + Environment.NewLine);
            }
            catch { }
        }
    }
}
