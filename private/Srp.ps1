# SRP / HKDF helpers for AWS Cognito auth (pure PowerShell on .NET types).
# Faithful port of pyhive-integration srp_crypto.py / hive_auth_async.py /
# device_registration.py (Pyhass/Pyhive @ 2cba27fb) and AWS's
# amazon-cognito-identity-js AuthenticationHelper. Hex strings are the
# canonical big-number representation throughout (as in the reference), so
# no little-endian BigInteger byte-array conversions are needed.
# See tests/SrpKnownAnswers.json + tests/Srp.Tests.ps1 for byte-exact proofs.

If (-not (Get-Variable -Name HiveSrpN -Scope Script -ErrorAction SilentlyContinue)) {
Set-Variable -Name HiveSrpN -Option Constant -Value (
    'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1' +
    '29024E088A67CC74020BBEA63B139B22514A08798E3404DD' +
    'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245' +
    'E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED' +
    'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D' +
    'C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F' +
    '83655D23DCA3AD961C62F356208552BB9ED529077096966D' +
    '670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B' +
    'E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9' +
    'DE2BCBF6955817183995497CEA956AE515D2261898FA0510' +
    '15728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64' +
    'ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7' +
    'ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6B' +
    'F12FFA06D98A0864D87602733EC86A64521F2B18177B200C' +
    'BBE117577A615D6C770988C0BAD946E208E24FA074E5AB31' +
    '43DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF'
)
}

# [bigint] (System.Numerics.BigInteger) ships with PowerShell 7.
function ConvertFrom-HiveHex {
    # Unsigned hex -> BigInteger. The leading '0' forces a non-negative parse.
    param([Parameter(Mandatory)][string]$Hex)
    Return [System.Numerics.BigInteger]::Parse('0' + $Hex.Trim(), [System.Globalization.NumberStyles]::HexNumber, [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-HiveHex {
    # BigInteger -> unpadded lowercase hex. Never pass negatives.
    # .NET prepends a '0' when the top nibble is >= 8 (so the string reads as
    # positive two's-complement); the reference (Python long_to_hex) has no
    # such padding, so strip it back to canonical minimal form.
    param([Parameter(Mandatory)][System.Numerics.BigInteger]$Value)
    $h = $Value.ToString('x', [System.Globalization.CultureInfo]::InvariantCulture)
    If ($Value -ge 0) { $h = $h.TrimStart('0'); If (-not $h) { $h = '0' } }
    Return $h
}

function Resize-HiveHex {
    # pyhive pad_hex: even-length hex with a high first nibble gets a '00'
    # prefix (keeps it positive if ever read as a signed int); odd gets '0'.
    param([Parameter(Mandatory)][string]$Hex)
    $h = $Hex.Trim().ToLowerInvariant()
    If ($h.Length % 2 -eq 1) { Return "0$h" }
    If ($h[0] -in @('8', '9', 'a', 'b', 'c', 'd', 'e', 'f')) { Return "00$h" }
    Return $h
}

function Convert-HiveHexToBytes {
    param([Parameter(Mandatory)][string]$Hex)
    $h = $Hex.Trim()
    If ($h.Length % 2 -eq 1) { $h = "0$h" }
    $bytes = [byte[]]::new($h.Length / 2)
    For ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16)
    }
    Return , $bytes
}

function Convert-HiveBytesToHex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    Return ([BitConverter]::ToString($Bytes) -replace '-', '').ToLowerInvariant()
}

function Invoke-HiveModPow {
    # BigInteger.ModPow is static: (base ^ exponent) mod modulus.
    param(
        [Parameter(Mandatory)][System.Numerics.BigInteger]$Base,
        [Parameter(Mandatory)][System.Numerics.BigInteger]$Exponent,
        [Parameter(Mandatory)][System.Numerics.BigInteger]$Modulus
    )
    Return [System.Numerics.BigInteger]::ModPow($Base, $Exponent, $Modulus)
}

function Get-HiveTrueMod {
    # BigInteger % can be negative; SRP needs a mathematical modulo.
    param(
        [Parameter(Mandatory)][System.Numerics.BigInteger]$Value,
        [Parameter(Mandatory)][System.Numerics.BigInteger]$Modulus
    )
    $r = $Value % $Modulus
    If ($r -lt 0) { $r += $Modulus }
    Return $r
}

function Get-HiveSha256Hex {
    # Matches pyhive hash_sha256: lowercase, zero-padded to 64 chars.
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($Bytes)
    Return (Convert-HiveBytesToHex $hash).PadLeft(64, '0')
}

function Get-HiveSha256HexOfHex {
    param([Parameter(Mandatory)][string]$Hex)
    Return (Get-HiveSha256Hex (Convert-HiveHexToBytes $Hex))
}

function Get-HiveHmacSha256 {
    param(
        [Parameter(Mandatory)][byte[]]$Key,
        [Parameter(Mandatory)][byte[]]$Message
    )
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($Key)
    Try { Return , $hmac.ComputeHash($Message) } Finally { $hmac.Dispose() }
}

function New-HiveRandomBytes {
    param([Parameter(Mandatory)][ValidateRange(1, 4096)][int]$Count)
    $bytes = [byte[]]::new($Count)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    Try { $rng.GetBytes($bytes) } Finally { $rng.Dispose() }
    Return , $bytes
}

function Get-HiveSrpConstantK {
    # k = SHA256(padHex(N) || padHex(g))
    $n = Get-HiveSha256HexOfHex ((Resize-HiveHex $script:HiveSrpN) + (Resize-HiveHex '2'))
    Return ConvertFrom-HiveHex $n
}

function New-HiveSrpEphemeral {
    # Fresh (a, A) per handshake: a = random(128 bytes) mod N; A = g^a mod N.
    $n = ConvertFrom-HiveHex $script:HiveSrpN
    $g = [System.Numerics.BigInteger]::One + [System.Numerics.BigInteger]::One
    $a = Get-HiveTrueMod (ConvertFrom-HiveHex (Convert-HiveBytesToHex (New-HiveRandomBytes 128))) $n
    $aValue = Invoke-HiveModPow -Base $g -Exponent $a -Modulus $n
    If ((Get-HiveTrueMod $aValue $n) -eq 0) {
        throw 'SRP safety check failed (A mod N == 0). Try again.'
    }
    Return [pscustomobject]@{
        SmallA = $a
        LargeA = $aValue
        HexA   = ConvertTo-HiveHex $aValue
    }
}

function Get-HiveHkdf {
    # HKDF-SHA256 with info 'Caldera Derived Key' + 0x01, first 16 bytes.
    # salt/ikm are raw byte arrays (as in pyhive compute_hkdf).
    param(
        [Parameter(Mandatory)][byte[]]$Ikm,
        [Parameter(Mandatory)][byte[]]$Salt
    )
    $prk = Get-HiveHmacSha256 $Salt $Ikm
    $infoBytes = [Text.Encoding]::UTF8.GetBytes('Caldera Derived Key') + [byte[]](1)
    $okm = Get-HiveHmacSha256 $prk $infoBytes
    return , $okm[0..15]
}

function CalculateHiveSrpU {
    param(
        [Parameter(Mandatory)][System.Numerics.BigInteger]$LargeA,
        [Parameter(Mandatory)][System.Numerics.BigInteger]$LargeB
    )
    $u = ConvertFrom-HiveHex (Get-HiveSha256HexOfHex ((Resize-HiveHex (ConvertTo-HiveHex $LargeA)) + (Resize-HiveHex (ConvertTo-HiveHex $LargeB))))
    If ($u -eq 0) { throw 'SRP error: U cannot be zero.' }
    Return $u
}

function Get-HivePasswordHkdf {
    # get_password_authentication_key equivalent. Returns the 16-byte HKDF
    # plus intermediate values (hex) for diagnostics/tests.
    param(
        [Parameter(Mandatory)][System.Numerics.BigInteger]$SmallA,
        [Parameter(Mandatory)][System.Numerics.BigInteger]$LargeA,
        [Parameter(Mandatory)][string]$UserId,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$PoolId,          # e.g. eu-west-1_SamNfoWtf
        [Parameter(Mandatory)][string]$SrpBHex,
        [Parameter(Mandatory)][string]$SaltHex
    )
    $n = ConvertFrom-HiveHex $script:HiveSrpN
    $g = [System.Numerics.BigInteger]::One + [System.Numerics.BigInteger]::One
    $k = Get-HiveSrpConstantK
    $b = ConvertFrom-HiveHex $SrpBHex
    $u = CalculateHiveSrpU $LargeA $b
    $poolIdShort = $PoolId.Split('_')[1]
    $usernamePasswordHash = Get-HiveSha256Hex ([Text.Encoding]::UTF8.GetBytes("$poolIdShort$UserId`:$Password"))
    $x = ConvertFrom-HiveHex (Get-HiveSha256HexOfHex ((Resize-HiveHex $SaltHex) + $usernamePasswordHash))
    $gModPowXn = Invoke-HiveModPow -Base $g -Exponent $x -Modulus $n
    $int2 = Get-HiveTrueMod ($b - ($k * $gModPowXn)) $n
    $s = Invoke-HiveModPow -Base $int2 -Exponent ($SmallA + ($u * $x)) -Modulus $n
    $hkdf = Get-HiveHkdf (Convert-HiveHexToBytes (Resize-HiveHex (ConvertTo-HiveHex $s))) (Convert-HiveHexToBytes (Resize-HiveHex (ConvertTo-HiveHex $u)))
    Return [pscustomobject]@{
        Hkdf = $hkdf
        UHex = ConvertTo-HiveHex $u
        XHex = ConvertTo-HiveHex $x
        SHex = ConvertTo-HiveHex $s
    }
}

function Get-HiveDeviceHkdf {
    # get_device_authentication_key equivalent: identity is
    # DeviceGroupKey + DeviceKey + ':' + DevicePassword (no pool prefix).
    param(
        [Parameter(Mandatory)][System.Numerics.BigInteger]$SmallA,
        [Parameter(Mandatory)][System.Numerics.BigInteger]$LargeA,
        [Parameter(Mandatory)][string]$DeviceGroupKey,
        [Parameter(Mandatory)][string]$DeviceKey,
        [Parameter(Mandatory)][string]$DevicePassword,
        [Parameter(Mandatory)][string]$SrpBHex,
        [Parameter(Mandatory)][string]$SaltHex
    )
    $n = ConvertFrom-HiveHex $script:HiveSrpN
    $g = [System.Numerics.BigInteger]::One + [System.Numerics.BigInteger]::One
    $k = Get-HiveSrpConstantK
    $b = ConvertFrom-HiveHex $SrpBHex
    $u = CalculateHiveSrpU $LargeA $b
    $combinedHash = Get-HiveSha256Hex ([Text.Encoding]::UTF8.GetBytes("$DeviceGroupKey$DeviceKey`:$DevicePassword"))
    $x = ConvertFrom-HiveHex (Get-HiveSha256HexOfHex ((Resize-HiveHex $SaltHex) + $combinedHash))
    $gModPowXn = Invoke-HiveModPow -Base $g -Exponent $x -Modulus $n
    $int2 = Get-HiveTrueMod ($b - ($k * $gModPowXn)) $n
    $s = Invoke-HiveModPow -Base $int2 -Exponent ($SmallA + ($u * $x)) -Modulus $n
    $hkdf = Get-HiveHkdf (Convert-HiveHexToBytes (Resize-HiveHex (ConvertTo-HiveHex $s))) (Convert-HiveHexToBytes (Resize-HiveHex (ConvertTo-HiveHex $u)))
    Return [pscustomobject]@{
        Hkdf = $hkdf
        UHex = ConvertTo-HiveHex $u
        XHex = ConvertTo-HiveHex $x
        SHex = ConvertTo-HiveHex $s
    }
}

function Get-HivePasswordClaimSignature {
    # base64 HMAC-SHA256(hkdf, poolIdShort || userId || secretBlockBytes || timestamp)
    param(
        [Parameter(Mandatory)][byte[]]$Hkdf,
        [Parameter(Mandatory)][string]$PoolId,
        [Parameter(Mandatory)][string]$UserId,
        [Parameter(Mandatory)][string]$SecretBlockB64,
        [Parameter(Mandatory)][string]$Timestamp
    )
    $poolIdShort = $PoolId.Split('_')[1]
    $msg = [Text.Encoding]::UTF8.GetBytes($poolIdShort) +
           [Text.Encoding]::UTF8.GetBytes($UserId) +
           [Convert]::FromBase64String($SecretBlockB64) +
           [Text.Encoding]::UTF8.GetBytes($Timestamp)
    Return [Convert]::ToBase64String((Get-HiveHmacSha256 $Hkdf $msg))
}

function Get-HiveDeviceClaimSignature {
    # Same shape but the message prefix is DeviceGroupKey || DeviceKey.
    param(
        [Parameter(Mandatory)][byte[]]$Hkdf,
        [Parameter(Mandatory)][string]$DeviceGroupKey,
        [Parameter(Mandatory)][string]$DeviceKey,
        [Parameter(Mandatory)][string]$SecretBlockB64,
        [Parameter(Mandatory)][string]$Timestamp
    )
    $msg = [Text.Encoding]::UTF8.GetBytes($DeviceGroupKey) +
           [Text.Encoding]::UTF8.GetBytes($DeviceKey) +
           [Convert]::FromBase64String($SecretBlockB64) +
           [Text.Encoding]::UTF8.GetBytes($Timestamp)
    Return [Convert]::ToBase64String((Get-HiveHmacSha256 $Hkdf $msg))
}

function New-HiveDeviceSecretVerifierConfig {
    # generate_hash_device equivalent, with caller-supplied device password
    # and salt so it is deterministic (tests) or random (production).
    param(
        [Parameter(Mandatory)][string]$DeviceGroupKey,
        [Parameter(Mandatory)][string]$DeviceKey,
        [string]$DevicePassword = $null,
        [string]$SaltHex = $null
    )
    If (-not $DevicePassword) { $DevicePassword = [Convert]::ToBase64String((New-HiveRandomBytes 40)) }
    If (-not $SaltHex) { $SaltHex = Resize-HiveHex (Convert-HiveBytesToHex (New-HiveRandomBytes 16)) }
    $n = ConvertFrom-HiveHex $script:HiveSrpN
    $g = [System.Numerics.BigInteger]::One + [System.Numerics.BigInteger]::One
    $combinedHash = Get-HiveSha256Hex ([Text.Encoding]::UTF8.GetBytes("$DeviceGroupKey$DeviceKey`:$DevicePassword"))
    $x = ConvertFrom-HiveHex (Get-HiveSha256HexOfHex ((Resize-HiveHex $SaltHex) + $combinedHash))
    $verifier = Resize-HiveHex (ConvertTo-HiveHex (Invoke-HiveModPow -Base $g -Exponent $x -Modulus $n))
    Return [pscustomobject]@{
        DevicePassword = $DevicePassword
        PasswordVerifierB64 = [Convert]::ToBase64String((Convert-HiveHexToBytes $verifier))
        SaltB64             = [Convert]::ToBase64String((Convert-HiveHexToBytes (Resize-HiveHex $SaltHex)))
        XHex                = ConvertTo-HiveHex $x
    }
}

function Get-HiveCognitoTimestamp {
    # Cognito expects e.g. "Fri Nov 6 14:03:05 UTC 2026" (non-zero-padded day).
    # 'MMM d' never zero-pads; pyhive achieves the same via a regex on %d.
    $utc = (Get-Date).ToUniversalTime()
    Return $utc.ToString("ddd MMM d HH:mm:ss 'UTC' yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
}
