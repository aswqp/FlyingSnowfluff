use framework "Foundation"
use scripting additions

on resolvedPathFor(inputPath)
    set pathString to current application's NSString's stringWithString:inputPath
    set standardPath to pathString's stringByStandardizingPath()
    return (standardPath's stringByResolvingSymlinksInPath()) as text
end resolvedPathFor

on run argv
    if (count of argv) is not 4 then error "expected: mode target-app destination alias-name" number 64
    set operationMode to item 1 of argv
    set targetPath to item 2 of argv
    set destinationPath to item 3 of argv
    set aliasName to item 4 of argv
    if operationMode is not "check" and operationMode is not "install" and operationMode is not "remove" then error "invalid mode" number 64
    set resolvedTargetPath to my resolvedPathFor(targetPath)

    set destinationAlias to POSIX file destinationPath as alias
    tell application "Finder"
        set destinationFolder to destinationAlias
        if exists item aliasName of destinationFolder then
            try
                set existingTarget to original item of (alias file aliasName of destinationFolder) as alias
                if (my resolvedPathFor(POSIX path of existingTarget)) is resolvedTargetPath then
                    if operationMode is "remove" then
                        delete item aliasName of destinationFolder
                        return "removed"
                    end if
                    return "reused"
                end if
            end try
            error "desktop shortcut conflict: " & aliasName number 17
        end if

        if operationMode is "check" then return "available"
        if operationMode is "remove" then return "absent"
        set targetAlias to POSIX file targetPath as alias
        make new alias file at destinationFolder to targetAlias with properties {name:aliasName}
    end tell
    return "created"
end run
