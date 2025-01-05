# rhubarb-geek-nz/powershell-sans-amsi

The goal of this project is to provide a version of [PowerShell](https://github.com/PowerShell/PowerShell) without:

1. AMSI logging
2. Telemetry
3. Automated version checking
4. Self-contained version of dotnet runtime

## AMSI logging

This will remove the code that formats and sends data to the AMSI API. This is a deliberate choice by this project. If you want AMSI support then use the standard builds.

## Telemetry

There will be no system to capture this information for this project so the code supporting it will be removed. Literally, nobody is interested in what you are doing with this project at runtime.

## Version checking

It is not this project's responsibility to update the host system. That is left to the installers. This project has no idea what is the appropriate version for your system.

## Self-contained version of dotnet runtime

Updates to dotnet will not require a re-release as it will use the [shared runtime](https://dotnet.microsoft.com/en-us/download/dotnet/8.0). This should also allow PowerShell code to use ASP.NET directly without versioning conflicts.

# Targets

The primary targets are `win-x64` and `win-arm64`. If you want a Debian release that uses the shared runtime then use [rhubarb-geek-nz/powershell-ubuntu](https://github.com/rhubarb-geek-nz/powershell-ubuntu).

# Origin

It starts with [PowerShell v7.4.5](https://github.com/PowerShell/PowerShell/releases/tag/v7.4.5) because .NET 8 is an LTS release.
