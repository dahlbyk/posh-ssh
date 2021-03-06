. $PSScriptRoot\Shared.ps1
. $PSScriptRoot\..\src\Globber.ps1
. $PSScriptRoot\..\src\ConfigParser.ps1
. $PSScriptRoot\..\src\OpenSsh.ps1

Describe "Config" {
    Context "Get-SshConfig" {
        It "Gets a single host" {
            $h = Get-SshConfig "tahoe1" -Path "$PSScriptRoot\fixtures\config"
            $h["HostName"]  | Should -Be "tahoe1.com"
        }
        It "Gets all hosts" {
            # Only 2 because the 2 wildcard hosts should be merged into the others.
            $h = Get-SshConfig -Path "$PSScriptRoot\fixtures\config"
            $h.Count | Should -Be 2
        }
        It "Gets host as raw node" {
            $h = Get-SshConfig "tahoe1" -Raw -Path "$PSScriptRoot\fixtures\config"
            $h.Param | Should -Be "Host"
            $h.Value | Should -Be "tahoe1"
        }
        It "Gets all hosts as raw nodes" {
            $h = Get-SshConfig -Raw -Path "$PSScriptRoot\fixtures\config"
            $h.Nodes.Count | Should -Be 7
        }
    }
    Context "Add-SshConnection"  {
        BeforeAll {
            Remove-Item "$PSScriptRoot\fixtures\configwrite" -ErrorAction Ignore
        }
        AfterEach {
            Remove-Item "$PSScriptRoot\fixtures\configwrite" -ErrorAction Ignore
        }
        It "Adds a connection" {
            Add-SshConnection -Name "foo" -Uri "example.com" `
                -IdentityFile "~/.ssh/id_rsa2" -User "bar" `
                -AdditionalOptions @{ Cows = "Moo" } `
                -Path "$PSScriptRoot\fixtures\configwrite"

            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output
            $h = $config.Compute("foo")

            $h["Host"] | Should -Be "foo"
            $h["HostName"] | Should -Be "example.com"
            $h["IdentityFile"] | Should -Be "~/.ssh/id_rsa2"
            $h["User"] | Should -Be "bar"
            $h["Cows"] | Should -Be "Moo"
        }
        It "Adds connection to the end of the file" {
            Add-Content "$PSScriptRoot\fixtures\configwrite" "Host bar`n  HostName example.com"

            Add-SshConnection -Name "foo1" -Uri "example.com" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            Add-SshConnection -Name "foo2" -Uri "example.com" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            Add-SshConnection -Name "foo3" -Uri "example.com" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output

            $config.Nodes[0].Value | Should -Be "bar"
            $config.Nodes[1].Value | Should -Be "foo1"
            $config.Nodes[2].Value | Should -Be "foo2"
            $config.Nodes[3].Value | Should -Be "foo3"
        }
        It "Adds connection to the end of the file but before the wildcard" {
            Add-Content "$PSScriptRoot\fixtures\configwrite" "Host *`n  ForwardAgent yes"

            Add-SshConnection -Name "foo1" -Uri "example.com" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            Add-SshConnection -Name "foo2" -Uri "example.com" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            Add-SshConnection -Name "foo3" -Uri "example.com" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output

            $config.Nodes[0].Value | Should -Be "foo1"
            $config.Nodes[1].Value | Should -Be "foo2"
            $config.Nodes[2].Value | Should -Be "foo3"
        }
        It "Adds connection to the end of the file after existing entries but before the wildcard" {
            Add-Content "$PSScriptRoot\fixtures\configwrite" "Host bar`n  HostName example.com`n`nHost *`n  ForwardAgent yes"

            Add-SshConnection -Name "foo1" -Uri "example.com" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            Add-SshConnection -Name "foo2" -Uri "example.com" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            Add-SshConnection -Name "foo3" -Uri "example.com" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output

            $config.Nodes[0].Value | Should -Be "bar"
            $config.Nodes[1].Value | Should -Be "foo1"
            $config.Nodes[2].Value | Should -Be "foo2"
            $config.Nodes[3].Value | Should -Be "foo3"
            $config.Nodes[4].Value | Should -Be "*"
        }
        It "Adds connection and splits out username" {
            Add-SshConnection -Name "foo" -Uri "bar@example.com" -Path "$PSScriptRoot\fixtures\configwrite"

            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output
            $h = $config.Compute("foo")

            $h["Host"] | Should -Be "foo"
            $h["HostName"] | Should -Be "example.com"
            $h["User"] | Should -Be "bar"
        }
        It "Adds connection with tunnel" {
            Add-SshConnection -Name "foo" -Uri "example.com" `
            -LocalTunnelPort 10001 -RemoteTunnelPort 10000 `
            -TunnelHost "foo" `
            -Path "$PSScriptRoot\fixtures\configwrite"

            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output
            $h = $config.Compute("foo")

            $h["LocalForward"] | Should -Be "10001 foo:10000"
        }
        It "Adds connection with tunnel and infers remote port" {
            Add-SshConnection -Name "foo" -Uri "example.com" `
            -LocalTunnelPort 10000 `
            -Path "$PSScriptRoot\fixtures\configwrite"

            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output
            $h = $config.Compute("foo")

            $h["LocalForward"] | Should -Be "10000 localhost:10000"
        }
        It "Adds connection with tunnel and infers local port" {
            Add-SshConnection -Name "foo" -Uri "example.com" `
            -RemoteTunnelPort 10000 `
            -Path "$PSScriptRoot\fixtures\configwrite"

            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output
            $h = $config.Compute("foo")

            $h["LocalForward"] | Should -Be "10000 localhost:10000"
        }
        It "Removes a connection" {
            Add-SshConnection -Name "foo" -Uri "example.com" `
                -Path "$PSScriptRoot\fixtures\configwrite"


            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output
            $h = $config.Compute("foo")

            $h["Host"] | Should -Be "foo"

            # It was successfully created. Now remove it.
            Remove-SshConnection -Name "foo"  -Path "$PSScriptRoot\fixtures\configwrite"

            $output = Get-Content "$PSScriptRoot\fixtures\configwrite" -Raw
            $config = Parse-SshConfig $output
            $h = $config.Compute("foo")
            $h | Should -Be $null

        }
    }
}
