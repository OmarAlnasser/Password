# Third-party notices

PC Doctor includes or downloads the following components. Each keeps its own license.

| Component | Version | License | Where |
|---|---|---|---|
| CommunityToolkit.Mvvm | 8.3.2 | MIT | App |
| Microsoft.Diagnostics.Tracing.TraceEvent | 3.1.13 | MIT | Broker (ETW traces) |
| System.Management, System.Diagnostics.EventLog, System.Security.Cryptography.ProtectedData and other .NET packages | see `Directory.Packages.props` | MIT | App, Broker |
| LibreHardwareMonitorLib | 0.9.6 | MPL-2.0 | Broker (sensors) |
| RAMSPDToolkit-NDD | 1.4.2 | MPL-2.0 | Broker, dependency of LibreHardwareMonitorLib. Its memory readout is turned off; PC Doctor never loads WinRing0. |
| DiskInfoToolkit | 1.1.2 | MPL-2.0 | Broker, dependency of LibreHardwareMonitorLib |
| BlackSharp.Core | 1.0.7 | MPL-2.0 | Broker, dependency of LibreHardwareMonitorLib |
| HidSharp | 2.6.4 | Apache-2.0 | Broker, dependency of LibreHardwareMonitorLib |
| Mono.Posix.NETStandard | 1.0.0 | See the package license (go.microsoft.com/fwlink/?linkid=869050) | Broker, dependency of LibreHardwareMonitorLib |
| DiskSpd | 2.2 | MIT | Bundled tool, hash-pinned (`third_party/licenses/DiskSpd-LICENSE.txt`) |
| PresentMon | 2.3.0 | MIT | Bundled tool, hash-pinned (`third_party/licenses/PresentMon-LICENSE.txt`) |
| Outfit | – | SIL Open Font License 1.1 | App font (`src/PcDoctor.App/Fonts/OFL-Outfit.txt`) |
| IBM Plex Sans Arabic | – | SIL Open Font License 1.1 | App font (`OFL-IBMPlexSansArabic.txt`) |
| JetBrains Mono | – | SIL Open Font License 1.1 | App font (`OFL-JetBrainsMono.txt`) |

MPL-2.0 source for the LibreHardwareMonitor packages is available from their NuGet package pages
and project repositories; PC Doctor does not modify them.

Not shipped, used only if already installed by the user: Microsoft Debugging Tools for Windows (cdb),
the Windows Performance Toolkit, and the PawnIO driver.
