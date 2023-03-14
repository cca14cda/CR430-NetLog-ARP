function Clean-MacAddress {

[OutputType([String], ParameterSetName = "Upper")]
    [OutputType([String], ParameterSetName = "Lower")]
    [CmdletBinding(DefaultParameterSetName = 'Upper')]
    param
    (
        [Parameter(ParameterSetName = 'Lower')]
        [Parameter(ParameterSetName = 'Upper')]
        [String]$MacAddress,

        [Parameter(ParameterSetName = 'Lower')]
        [Parameter(ParameterSetName = 'Upper')]
        [ValidateSet(':', 'None', '.', "-")]
        $Separator,

        [Parameter(ParameterSetName = 'Upper')]
        [Switch]$Uppercase,

        [Parameter(ParameterSetName = 'Lower')]
        [Switch]$Lowercase
    )

    BEGIN {
        # Initial Cleanup
        $MacAddress = $MacAddress -replace "-", "" #Replace Dash
        $MacAddress = $MacAddress -replace ":", "" #Replace Colon
        $MacAddress = $MacAddress -replace "/s", "" #Remove whitespace
        $MacAddress = $MacAddress -replace " ", "" #Remove whitespace
        $MacAddress = $MacAddress -replace "\.", "" #Remove dots
        $MacAddress = $MacAddress.trim() #Remove space at the beginning
        $MacAddress = $MacAddress.trimend() #Remove space at the end
    }
    PROCESS {
        IF ($PSBoundParameters['Uppercase']) {
            $MacAddress = $macaddress.toupper()
        }
        IF ($PSBoundParameters['Lowercase']) {
            $MacAddress = $macaddress.tolower()
        }
        IF ($PSBoundParameters['Separator']) {
            IF ($Separator -ne "None") {
                $MacAddress = $MacAddress -replace '(..(?!$))', "`$1$Separator"
            }
            
        }
    }

   

    END {
        
        $RegEx = "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})|([0-9A-Fa-f]{2}){6}$"
            if ($MacAddress -match $RegEx) {
		return $MacAddress
	} else {
		return $false
	}
        

    }
    
}

