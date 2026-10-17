using System.Windows;
using System.Windows.Controls;
using PlayniteExporterPlugin.Configuration;

namespace PlayniteExporterPlugin.Views
{
    public partial class SettingsView : UserControl
    {
        public SettingsView()
        {
            InitializeComponent();
            Loaded += SettingsView_Loaded;
        }

        private void SettingsView_Loaded(object sender, RoutedEventArgs e)
        {
            if (DataContext is ExporterSettingsViewModel vm)
            {
                if (!string.IsNullOrEmpty(vm.Settings.GoogleClientSecret))
                {
                    ClientSecretBox.Password = vm.Settings.GoogleClientSecret;
                }
                vm.RefreshGoogleAuthState();
            }
        }

        private void ClientSecretBox_PasswordChanged(object sender, RoutedEventArgs e)
        {
            if (DataContext is ExporterSettingsViewModel vm)
            {
                vm.Settings.GoogleClientSecret = ClientSecretBox.Password;
                vm.RefreshGoogleAuthState();
            }
        }
    }
}
