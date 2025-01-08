#!/usr/bin/env pwsh
# Copyright (c) 2025 Roger Brown.
# Licensed under the MIT License.

param(
	$PowerShellVersion = '7.4.5',
	$CertificateThumbprint = '601A8B683F791E51F647D34AD102C38DA4DDB65F'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ReleaseTag = "v$PowerShellVersion"

trap
{
	throw $PSItem
}

$xmlDoc = [System.Xml.XmlDocument](Get-Content -LiteralPath 'PowerShell.Common.props')
$nsMgr = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $xmlDoc.NameTable
$nsmgr.AddNamespace('ms', 'http://schemas.microsoft.com/developer/msbuild/2003')
$CompanyName = $xmlDoc.SelectSingleNode("/ms:Project/ms:PropertyGroup/ms:Company", $nsmgr).FirstChild.Value
$ProductName = $xmlDoc.SelectSingleNode("/ms:Project/ms:PropertyGroup/ms:Product", $nsmgr).FirstChild.Value

Import-Module .\build.psm1

if ($IsWindows)
{
	dotnet tool restore

	If ( $LastExitCode -ne 0 )
	{
		Exit $LastExitCode
	}

	$codeSignCertificate = Get-ChildItem -path Cert:\ -Recurse -CodeSigningCert | Where-Object { $_.Thumbprint -eq $CertificateThumbprint }

	if ($codeSignCertificate.Count -ne 1)
	{
		Write-Error "Error with certificate - $CertificateThumbprint"
	}

	if ( -not ( Test-Path -LiteralPath 'amsi-1.0.0.zip' ))
	{
		Invoke-WebRequest -Uri 'https://github.com/rhubarb-geek-nz/powershell-amsi/releases/download/1.0.0/amsi-1.0.0.zip' -OutFile 'amsi-1.0.0.zip'
	}

	if ( -not ( Test-Path -LiteralPath 'amsi' ))
	{
		Expand-Archive 'amsi-1.0.0.zip' -DestinationPath 'amsi'
	}

	$DotNetAppRuntime = "$($Env:ProgramFiles)\dotnet\shared\Microsoft.NETCore.App\8.0.11"

	if ( -not ( Test-Path -LiteralPath $DotNetAppRuntime -PathType Container ) )
	{
		Write-Error $DotNetAppRuntime
	}

	$Env:POWERSHELL_MSI_COMMENTS = (git describe).Trim()

	$Revision = $Env:POWERSHELL_MSI_COMMENTS.Split('-')[1]

	$PowerShellVersion = "$PowerShellVersion.$Revision"

	$ArchList = @(
		@{
			Arch = 'x86'
			Runtime = 'win7-x86'
			UpgradeCode = '1D00683B-0F84-4DB8-A64F-2F98AD42FE06'
			Is64bit = $false
			Win64 = 'no'
			Platform = 'x86'
			ProgramFilesFolder = 'ProgramFilesFolder'
			InstallerVersion = '200'
			EnvironmentGuid = '9F718501-562E-4C41-97E0-09E93D6698EA'
			ApplicationShortcutGuid = '2B6CE39E-287B-4B1F-AE34-9AAAB68EF150'
		},
		@{
			Arch = 'x64'
			Runtime = 'win7-x64'
			UpgradeCode = '31AB5147-9A97-4452-8443-D9709F0516E1'
			Is64bit = $true
			Win64 = 'yes'
			Platform = 'x64'
			ProgramFilesFolder = 'ProgramFiles64Folder'
			InstallerVersion = '200'
			EnvironmentGuid = '8AC5A84A-6989-4023-BBC9-2CF289952E35'
			ApplicationShortcutGuid = 'E03DA96F-2A57-49A2-BB95-C1B73768CD17'
		},
		@{
			Arch = 'arm64'
			Runtime = 'win-arm64'
			UpgradeCode = '75C68AB2-09D8-46B8-B697-D829BDD4C94F'
			Is64bit = $true
			Win64 = 'yes'
			Platform = 'arm64'
			ProgramFilesFolder = 'ProgramFiles64Folder'
			InstallerVersion = '500'
			EnvironmentGuid = '68AED3CC-F112-4400-8839-6C029532ECDD'
			ApplicationShortcutGuid = '2E423858-944E-449E-9A78-3506E2964740'
		}
	)

	foreach ($Arch in $ArchList)
	{
		Start-PSBuild -Configuration Release -Runtime $Arch.Runtime -ReleaseTag $ReleaseTag

		$PublishDir = "src\powershell-win-core\bin\Release\net8.0\$($Arch.Runtime)\publish"

		Copy-Item "amsi\$($Arch.Arch)\amsi.dll" "$PublishDir\amsi.dll"

		foreach ($Name in 'pwsh.dll', 'pwsh.exe')
		{
			Write-Information "Signing $PublishDir\$Name"
			$null = Set-AuthenticodeSignature -FilePath "$PublishDir\$Name" -HashAlgorithm 'SHA256' -Certificate $codeSignCertificate -TimestampServer 'http://timestamp.digicert.com'
		}

		Get-ChildItem -LiteralPath 'src' -Directory | ForEach-Object {
			$Name = $_.Name
			$FullPath = "$PublishDir\$Name.dll"
			if (Test-Path -LiteralPath $FullPath)
			{
				Write-Information "Signing $FullPath"
				$null = Set-AuthenticodeSignature -FilePath $FullPath -HashAlgorithm 'SHA256' -Certificate $codeSignCertificate -TimestampServer 'http://timestamp.digicert.com'
			}
		}

		$pdb = Get-ChildItem -LiteralPath $PublishDir -Filter '*.pdb' -Recurse -File

		if ($pdb)
		{
			$pdb | ForEach-Object {
				Write-Information "del $($_.FullName)"
			}
			$pdb | Remove-Item
		}

		$dlls = Get-ChildItem -LiteralPath $PublishDir -Filter '*.dll' -File

		foreach ($dll in $dlls)
		{
			$Name = $dll.Name

			if (Test-Path -LiteralPath "$DotNetAppRuntime\$Name" -PathType Leaf)
			{
				Write-Information "del $($dll.FullName)"
				Remove-Item $dll
			}
		}

		$MsiStem = "PowerShellSansAMSI-$PowerShellVersion-win-$($Arch.Arch)"

@'
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="$(var.ProductName) ($(var.Platform))" Language="1033" Version="$(var.PowerShellVersion)" Manufacturer="$(var.CompanyName)" UpgradeCode="$(var.UpgradeCode)">
    <Package InstallerVersion="$(var.InstallerVersion)" Compressed="yes" InstallScope="perMachine" Platform="$(var.Platform)" Description="$(var.ProductName) $(var.PowerShellVersion) $(var.Platform)" Comments="$(env.POWERSHELL_MSI_COMMENTS)" />
    <MediaTemplate EmbedCab="yes" />
    <Feature Id="ProductFeature" Title="setup" Level="1">
      <ComponentGroupRef Id="ProductComponents" />
    </Feature>
    <Upgrade Id="{$(var.UpgradeCode)}">
      <UpgradeVersion Maximum="$(var.PowerShellVersion)" Property="OLDPRODUCTFOUND" OnlyDetect="no" IncludeMinimum="yes" IncludeMaximum="no" />
    </Upgrade>
    <InstallExecuteSequence>
      <RemoveExistingProducts After="InstallInitialize" />
      <WriteEnvironmentStrings/>
    </InstallExecuteSequence>
    <DirectoryRef Id="INSTALLDIR">
      <Component Id ="setEnviroment" Guid="$(var.EnvironmentGuid)" Win64="$(var.Win64)">
        <CreateFolder />
        <Environment Id="PATH" Action="set" Name="PATH" Part="last" Permanent="no" System="yes" Value="[INSTALLDIR]" />
       </Component>
    </DirectoryRef>
    <Feature Id="PathFeature" Title="PATH" Level="1" Absent="disallow" AllowAdvertise="no" Display="hidden" >
      <ComponentRef Id="setEnviroment"/>
      <ComponentRef Id="ApplicationShortcut" />
      <ComponentRef Id="pwsh.exe" />
    </Feature>
    <DirectoryRef Id="ApplicationProgramsFolder">
      <Component Id="ApplicationShortcut" Guid="$(var.ApplicationShortcutGuid)">
        <Shortcut Id="ApplicationStartMenuShortcut"
                  Name="PowerShell 7 ($(var.Platform))"
                  Description="PowerShell $(var.PowerShellVersion) for $(var.Platform)"
                  Target="[#pwsh.exe]"
                  Arguments="-WorkingDirectory ~"
                  WorkingDirectory="INSTALLDIR"/>
        <RemoveFolder Id="CleanUpShortCut" Directory="ApplicationProgramsFolder" On="uninstall"/>
        <RegistryValue Root="HKCU" Key="Software\Microsoft\PowerShell7" Name="installed" Type="integer" Value="1" KeyPath="yes"/>
      </Component>
    </DirectoryRef>
  </Product>
  <Fragment>
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="$(var.ProgramFilesFolder)">
        <Directory Id="INSTALLPRODUCT" Name="PowerShell">
          <Directory Id="INSTALLDIR" Name="7" />
        </Directory>
      </Directory>
      <Directory Id="ProgramMenuFolder" Name="ProgramMenuFolder" >
        <Directory Id="ApplicationProgramsFolder" Name="PowerShell 7"/>
      </Directory>
    </Directory>
  </Fragment>
  <Fragment>
    <ComponentGroup Id="ProductComponents">
      <Component Id="pwsh.exe" Guid="*" Directory="INSTALLDIR" Win64="$(var.Win64)">
        <File Id="pwsh.exe" KeyPath="yes" Source="PublishDir\pwsh.exe" />
      </Component>
    </ComponentGroup>
  </Fragment>
</Wix>
'@.Replace('PublishDir',$PublishDir) | dotnet dir2wxs -o "$MsiStem.wxs" -s $PublishDir

		If ( $LastExitCode -ne 0 )
		{
			Exit $LastExitCode
		}

		& "$ENV:WIX\bin\candle.exe" `
				"$MsiStem.wxs" `
				-nologo `
				-ext WixUtilExtension `
				"-dWin64=$($Arch.Win64)" `
				"-dPlatform=$($Arch.Platform)" `
				"-dProgramFilesFolder=$($Arch.ProgramFilesFolder)" `
				"-dUpgradeCode=$($Arch.UpgradeCode)" `
				"-dInstallerVersion=$($Arch.InstallerVersion)" `
				"-dEnvironmentGuid=$($Arch.EnvironmentGuid)" `
				"-dApplicationShortcutGuid=$($Arch.ApplicationShortcutGuid)" `
				"-dCompanyName=$CompanyName" `
				"-dProductName=$ProductName" `
				"-dPowerShellVersion=$PowerShellVersion"

		If ( $LastExitCode -ne 0 )
		{
			Exit $LastExitCode
		}

		& "$ENV:WIX\bin\light.exe" -sw1076 -nologo -cultures:null -out "$MsiStem.msi" "$MsiStem.wixobj" -ext WixUtilExtension

		If ( $LastExitCode -ne 0 )
		{
			Exit $LastExitCode
		}

		$null = Set-AuthenticodeSignature -FilePath "$MsiStem.msi" -HashAlgorithm 'SHA256' -Certificate $codeSignCertificate -TimestampServer 'http://timestamp.digicert.com'

		foreach ($WixExt in 'wxs','wixobj','wixpdb')
		{
			Remove-Item "$MsiStem.$WixExt"
		}
	}
}

If ($IsLinux)
{
	$Maintainer = git config user.email

	if (-not $Maintainer)
	{
		throw "No Maintainer"
	}

	Start-PSBootstrap

	$ArchList = @(
		@{
			Arch = 'armhf'
			Runtime = 'linux-arm'
		},
		@{
			Arch = 'amd64'
			Runtime = 'linux-x64'
		},
		@{
			Arch = 'arm64'
			Runtime = 'linux-arm64'
		}
	)

	$Revision = (git describe).Trim().Split('-')[1]

	$PowerShellVersion = "$PowerShellVersion-$Revision.sansamsi"

$pem = @'
-----BEGIN CERTIFICATE-----
MIIDrDCCApSgAwIBAgIUTqiToBIZNd1yUEfo0miaBeySJTYwDQYJKoZIhvcNAQEL
BQAwHTEbMBkGA1UEAwwScmh1YmFyYi1nZWVrLW56IENBMCAXDTIzMDQwMTA1NTk1
MVoYDzIxMjMwMzA4MDU1OTUxWjBQMTQwMgYJKoZIhvcNAQkBFiVyaHViYXJiLWdl
ZWstbnpAdXNlcnMuc291cmNlZm9yZ2UubmV0MRgwFgYDVQQDEw9yaHViYXJiLWdl
ZWstbnowggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQDsCelvzGsvxTOy
WHgozBArQvIaXpH+UUwwPvqQ851IuUhrmNy9q7C+TSCWkCSAL0YrE/p5LDnHuqoH
JGCtj5ToimRQaJfDv0dRjzEwZloT4/7zRg7MQwDaBXQuVN8gvWOTKKm4ucn49Bxy
p9uUdglxcvWOxqWD3J+lL4JIQ6k4t9yNLUJSqqIM87E55krtQLowtFRx6cb7y3L4
1SsEYEI3mncLT/NJ+0NvLaLtIMhhFNcuCMdC4yIlRbW9EN7sCsSjT11Si9gRTksO
LzHGBe9u/PnZv0M7euWgpjMLq5WAdHtthSqmK8T7z+Kr7Ig1053LFax6c8h6YVk8
qyM0LBxlp+n4/JYhBU/jbpMbyv9ljgfEJeF64bcd4KgLLNi5l5YwMgzfXAt0M6hD
UwGe4qRkerCqfmQQsM1kS02Afj8X37uIn6kLtC2boynLJAI8hEQwFiw7d0FMEA/Z
6CGcFUMM+wY+tqVCbMD3R9GrSS3G22SxkKnw0yfkuUv9gZcsGEcCAwEAAaMvMC0w
DAYDVR0TAQH/BAIwADAdBgNVHSUEFjAUBggrBgEFBQcDAwYIKwYBBQUHAwQwDQYJ
KoZIhvcNAQELBQADggEBABwMuceP7rESJioVuDqU1uOwbOKoQHTu6FfFfaM/csuF
/38UPnqsrq1iPijboy41/11wuiTwrkOyx0PbmwnMOWoh3PORvA/Kou+gCkZZy4Mp
aSgI68HrCwhHguUkRCEgpkNNLNrFP+6ls6SdCbqfTI0yWlQQKSMQ2ywTCHRqR0fx
RmYD45ymRELNqNQgq3MS/IZMLd/tHFKIleahBH2dPC71ppirZmpVep3QkiDDwdkG
fQtXz7vpN/rFCcFS5qt0wF02WZVUEGEPCdmxp2UmRhmeAMrGBzxq93fdEyq0/MsL
YFr03haC8XYc/ud0s9Rj2ZCxMAy+HQbXcAT2z+fKlWw=
-----END CERTIFICATE-----
'@

	$codeSignCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($pem)

	foreach ($Arch in $ArchList)
	{
		Start-PSBuild -Configuration Release -Runtime $Arch.Runtime -ReleaseTag $ReleaseTag

		$PublishDir = "src/powershell-unix/bin/Release/net8.0/$($Arch.Runtime)/publish"

		foreach ($Filter in '*.r2rmap', '*.pdb')
		{
			$Files = Get-ChildItem -LiteralPath $PublishDir -Filter $Filter -File -Recurse

			$Files | Remove-Item
		}

		foreach ($File in 'libcrypto.so.1.0.0', 'libssl.so.1.0.0')
		{
			if (Test-Path "$PublishDir/$File")
			{
				Remove-Item "$PublishDir/$File"
			}
		}

		$OutputFile = "powershell_$($PowerShellVersion)_$($Arch.Arch).deb"

		if (Test-Path $OutputFile)
		{
			Remove-Item $OutputFile
		}

		$Null = New-Item 'control',
			'data',
			'data/usr',
			'data/usr/bin',
			'data/usr/local/share/man/man1',
			'data/opt',
			'data/opt/microsoft',
			'data/opt/microsoft/powershell' -ItemType Directory

		foreach ($Name in 'pwsh.dll')
		{
			Write-Information "Signing $PublishDir/$Name"
			$null = Set-AuthenticodeSignature -FilePath "$PublishDir/$Name" -HashAlgorithm 'SHA256' -Certificate $codeSignCertificate -TimestampServer 'http://timestamp.digicert.com'
		}

		Get-ChildItem -LiteralPath 'src' -Directory | ForEach-Object {
			$Name = $_.Name
			$FullPath = "$PublishDir/$Name.dll"
			if (Test-Path -LiteralPath $FullPath)
			{
				Write-Information "Signing $FullPath"
				$null = Set-AuthenticodeSignature -FilePath $FullPath -HashAlgorithm 'SHA256' -Certificate $codeSignCertificate -TimestampServer 'http://timestamp.digicert.com'
			}
		}

		Copy-Item $PublishDir 'data/opt/microsoft/powershell/7' -Recurse

		$Size = sh -c 'du -sk data | while read A B; do echo $A; done'
@"
Package: powershell
Version: $PowerShellVersion
License: MIT License
Vendor: Microsoft Corporation
Architecture: $($Arch.Arch)
Maintainer: $Maintainer
Installed-Size: $Size
Depends: dotnet-runtime-8.0 (>= 8.0.11)
Section: shells
Priority: optional
Homepage: https://microsoft.com/powershell
Description: PowerShell is an automation and configuration management platform.
 It consists of a cross-platform command-line shell and associated scripting language.
"@ | Set-Content 'control/control'

@'
set -e
case "$1" in
	(configure)
		add-shell /usr/bin/pwsh
		;;
	(*)
		;;
esac
'@ | Set-Content 'control/postinst'

@'
set -e
case "$1" in
	(remove)
		remove-shell /usr/bin/pwsh
		remove-shell /opt/microsoft/powershell/7/pwsh
		;;
	(*)
		;;
esac
'@ | Set-Content 'control/postrm'

'2.0' | Set-Content 'debian-binary'

		foreach ($cmd in 'find data -type f | xargs chmod -x',
			'chmod ugo+x data/opt/microsoft/powershell/7/pwsh control/postinst control/postrm',
			'ln -s /opt/microsoft/powershell/7/pwsh data/usr/bin/pwsh',
			'gzip < assets/manpage/pwsh.1 > data/usr/local/share/man/man1/pwsh.1.gz',
			'cd data ; find * -type f -print0 | xargs -r0 md5sum > ../control/md5sum',
			'cd data ; tar  --owner=0 --group=0 --create --xz --file ../data.tar.xz ./*',
			'cd control ; tar  --owner=0 --group=0 --create --xz --file ../control.tar.xz ./*',
			"ar r $OutputFile debian-binary control.tar.xz data.tar.xz",
			'rm -rf debian-binary control.tar.xz data.tar.xz data control')
		{
			sh -e -c $cmd

			if ($LastExitCode)
			{
				exit $LastExitCode
			}
		}
	}
}
