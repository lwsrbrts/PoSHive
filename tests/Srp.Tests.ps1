# Byte-exact known-answer tests for the SRP/HKDF port (private/Srp.ps1).
# Vectors in SrpKnownAnswers.json were derived once from the reference
# pyhive implementation (Pyhass/Pyhive @ 2cba27fb) and confirmed against
# live logins, so a pass proves wire compatibility.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'PoSHive.psd1') -Force
    $script:Kat = Get-Content (Join-Path $PSScriptRoot 'SrpKnownAnswers.json') -Raw | ConvertFrom-Json
    $script:M = Get-Module PoSHive
}

Describe 'SRP known-answer vectors' {
    It 'computes the RFC 5054 group constant k' {
        $k = & $M { ConvertTo-HiveHex (Get-HiveSrpConstantK) }
        $k | Should -Be $Kat.constants.k
    }

    It 'padHex handles odd-length input' {
        & $M { Resize-HiveHex $args[0] } $Kat.padHex.odd_length.in | Should -Be $Kat.padHex.odd_length.out
    }
    It 'padHex handles high nibble' {
        & $M { Resize-HiveHex $args[0] } $Kat.padHex.high_nibble.in | Should -Be $Kat.padHex.high_nibble.out
    }
    It 'padHex handles even low nibble' {
        & $M { Resize-HiveHex $args[0] } $Kat.padHex.even_low_nibble.in | Should -Be $Kat.padHex.even_low_nibble.out
    }

    It 'derives A = g^a mod N' {
        $largeA = & $M {
            $n = ConvertFrom-HiveHex $script:HiveSrpN
            $g = [System.Numerics.BigInteger]::One + [System.Numerics.BigInteger]::One
            $a = ConvertFrom-HiveHex $args[0]
            ConvertTo-HiveHex ([System.Numerics.BigInteger]::ModPow($g, $a, $n))
        } $Kat.inputs.small_a_hex
        $largeA | Should -Be $Kat.passwordVerifier.large_a_hex
    }
}

Describe 'Password verifier path (USER_SRP_AUTH)' {
    BeforeAll {
        $Kat = $script:Kat
        $M = $script:M
        $KatJson = $Kat | ConvertTo-Json -Depth 10 -Compress
        $script:Pv = & $M {
            $k = $args[0] | ConvertFrom-Json
            $n = ConvertFrom-HiveHex $script:HiveSrpN
            $g = [System.Numerics.BigInteger]::One + [System.Numerics.BigInteger]::One
            $smallA = ConvertFrom-HiveHex $k.inputs.small_a_hex
            $largeA = [System.Numerics.BigInteger]::ModPow($g, $smallA, $n)
            $pv = Get-HivePasswordHkdf -SmallA $smallA -LargeA $largeA -UserId $k.inputs.user_id `
                -Password $k.inputs.password -PoolId $k.inputs.pool_id `
                -SrpBHex $k.inputs.srp_b_hex -SaltHex $k.inputs.salt_hex
            $sig = Get-HivePasswordClaimSignature -Hkdf ([byte[]]$pv.Hkdf) -PoolId $k.inputs.pool_id `
                -UserId $k.inputs.user_id -SecretBlockB64 $k.inputs.secret_block_b64 -Timestamp $k.inputs.timestamp
            @{
                U = $pv.UHex; X = $pv.XHex; S = $pv.SHex
                Hkdf = [Convert]::ToBase64String([byte[]]$pv.Hkdf)
                Sig = $sig
            }
        } $KatJson
    }

    It 'derives u'      { $script:Pv.U    | Should -Be $Kat.passwordVerifier.u_hex }
    It 'derives x'      { $script:Pv.X    | Should -Be $Kat.passwordVerifier.x_hex }
    It 'derives S'      { $script:Pv.S    | Should -Be $Kat.passwordVerifier.s_hex }
    It 'derives HKDF key'   { $script:Pv.Hkdf | Should -Be $Kat.passwordVerifier.hkdf_b64 }
    It 'signs the password claim' { $script:Pv.Sig | Should -Be $Kat.passwordVerifier.password_claim_signature_b64 }
}

Describe 'Device registration and device-login paths' {
    BeforeAll {
        $Kat = $script:Kat
        $KatJson = $Kat | ConvertTo-Json -Depth 10 -Compress
        $script:Dv = & $M {
            $k = $args[0] | ConvertFrom-Json
            $dv = New-HiveDeviceSecretVerifierConfig -DeviceGroupKey $k.inputs.device_group_key `
                -DeviceKey $k.inputs.device_key -DevicePassword $k.inputs.device_password `
                -SaltHex $k.inputs.device_salt_hex
            $n = ConvertFrom-HiveHex $script:HiveSrpN
            $g = [System.Numerics.BigInteger]::One + [System.Numerics.BigInteger]::One
            $smallA = ConvertFrom-HiveHex $k.inputs.small_a_hex
            $largeA = [System.Numerics.BigInteger]::ModPow($g, $smallA, $n)
            $devPV = Get-HiveDeviceHkdf -SmallA $smallA -LargeA $largeA -DeviceGroupKey $k.inputs.device_group_key `
                -DeviceKey $k.inputs.device_key -DevicePassword $k.inputs.device_password `
                -SrpBHex $k.inputs.srp_b_hex -SaltHex $k.inputs.device_salt_hex
            $devSig = Get-HiveDeviceClaimSignature -Hkdf ([byte[]]$devPV.Hkdf) -DeviceGroupKey $k.inputs.device_group_key `
                -DeviceKey $k.inputs.device_key -SecretBlockB64 $k.inputs.secret_block_b64 -Timestamp $k.inputs.timestamp
            @{
                Verifier = $dv.PasswordVerifierB64; Salt = $dv.SaltB64; X = $dv.XHex
                LoginU = $devPV.UHex; LoginX = $devPV.XHex; LoginS = $devPV.SHex
                LoginHkdf = [Convert]::ToBase64String([byte[]]$devPV.Hkdf)
                LoginSig = $devSig
            }
        } $KatJson
    }

    It 'builds ConfirmDevice PasswordVerifier' { $script:Dv.Verifier | Should -Be $Kat.deviceRegistration.verifier_config.PasswordVerifier }
    It 'builds ConfirmDevice Salt'              { $script:Dv.Salt     | Should -Be $Kat.deviceRegistration.verifier_config.Salt }
    It 'derives device registration x'          { $script:Dv.X        | Should -Be $Kat.deviceRegistration.x_hex }
    It 'device login derives u'                 { $script:Dv.LoginU   | Should -Be $Kat.devicePasswordVerifier.u_hex }
    It 'device login derives x'                 { $script:Dv.LoginX   | Should -Be $Kat.devicePasswordVerifier.x_hex }
    It 'device login derives S'                 { $script:Dv.LoginS   | Should -Be $Kat.devicePasswordVerifier.s_hex }
    It 'device login derives HKDF key'          { $script:Dv.LoginHkdf | Should -Be $Kat.devicePasswordVerifier.hkdf_b64 }
    It 'device login signs the claim'           { $script:Dv.LoginSig | Should -Be $Kat.devicePasswordVerifier.password_claim_signature_b64 }
}
