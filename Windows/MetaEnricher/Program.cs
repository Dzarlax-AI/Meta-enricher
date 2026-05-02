using System;
using Microsoft.UI.Xaml;

namespace MetaEnricher;

public static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        // WindowsAppSDKSelfContained=true: runtime DLLs are in the output directory,
        // loaded automatically — Bootstrap.Initialize() must NOT be called here.
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(p =>
        {
            var context = new Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(
                Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
            System.Threading.SynchronizationContext.SetSynchronizationContext(context);
            _ = new App();
        });
    }
}
