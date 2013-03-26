#!/bin/sh
# -*- tcl -*- \
exec tclsh "$0" ${1+"$@"}

# --------------------------------------------------------------
# Installer for Tklib. The lowest version of the tcl core supported
# by any module is 8.2. So we enforce that the installer is run with
# at least that.

package require Tcl 8.2

set distribution   [file dirname [info script]]
lappend auto_path  [file join $distribution modules]


# --------------------------------------------------------------
# Version information for tklib.
# List of modules to install (and definitions guiding the process)

proc package_name    {text} {global package_name    ; set package_name    $text}
proc package_version {text} {global package_version ; set package_version $text}
proc dist_exclude    {path} {}
proc critcl       {name files} {}
proc critcl_main  {name files} {}
proc critcl_notes {text} {}

source [file join $distribution support installation version.tcl] ; # Get version information.
source [file join $distribution support installation modules.tcl] ; # Get list of installed modules.
source [file join $distribution support installation actions.tcl] ; # Get code to perform install actions.

set package_nv ${package_name}-${package_version}
set package_name_cap [string toupper [string index $package_name 0]][string range $package_name 1 end]

# --------------------------------------------------------------
# Low-level commands of the installation engine.

proc gen_main_index {outdir package version} {
    global config

    log "\nGenerating [file join $outdir pkgIndex.tcl]"
    if {$config(dry)} {return}

    set   index [open [file join $outdir pkgIndex.tcl] w]

    puts $index "# Tcl package index file, version 1.1"
    puts $index "# Do NOT edit by hand.  Let $package install generate this file."
    puts $index "# Generated by $package installer for version $version"

    puts $index {
# All tklib packages need Tcl 8 (use [namespace])
if {![package vsatisfies [package provide Tcl] 8]} {return}

# Extend the auto_path to make tklib packages available
if {[lsearch -exact $::auto_path $dir] == -1} {
    lappend ::auto_path $dir
}

# For Tcl 8.3.1 and later, that's all we need
if {[package vsatisfies [package provide Tcl] 8.4]} {return}
if {(0 == [catch {
    package vcompare [info patchlevel] [info patchlevel]
}]) && (
    [package vcompare [info patchlevel] 8.3.1] >= 0
)} {return}

# For older Tcl releases, here are equivalent contents
# of the pkgIndex.tcl files of all the modules

if {![package vsatisfies [package provide Tcl] 8.0]} {return}
}
    puts $index ""
    puts $index "set maindir \$dir"

    foreach pi [lsort [glob -nocomplain [file join $outdir * pkgIndex.tcl]]] {
	set subdir [file tail [file dirname $pi]]
	puts $index "set dir \[file join \$maindir [list $subdir]\] ;\t source \[file join \$dir pkgIndex.tcl\]"
    }

    puts  $index "unset maindir"
    puts  $index ""
    close $index
    return
}

proc xcopyfile {src dest} {
    # dest can be dir or file
    run file copy -force $src $dest
    return
}

proc xcopy {src dest recurse {pattern *}} {
    run file mkdir $dest

    if {[string equal $pattern *] || !$recurse} {
	foreach file [glob [file join $src $pattern]] {
	    set base [file tail $file]
	    set sub  [file join $dest $base]

	    if {0 == [string compare CVS $base]} {continue}

	    if {[file isdirectory $file]} then {
		if {$recurse} {
		    run file mkdir  $sub
		    xcopy $file $sub $recurse $pattern

		    # If the directory is empty after the recursion remove it again.
		    if {![llength [glob -nocomplain [file join $sub *]]]} {
			file delete $sub
		    }
		}
	    } else {
		xcopyfile $file $sub
	    }
	}
    } else {
	foreach file [glob [file join $src *]] {
	    set base [file tail $file]
	    set sub  [file join $dest $base]

	    if {[string equal CVS $base]} {continue}

	    if {[file isdirectory $file]} then {
		if {$recurse} {
		    run file mkdir $sub
		    xcopy $file $sub $recurse $pattern

		    # If the directory is empty after the recursion remove it again.
		    if {![llength [glob -nocomplain [file join $sub *]]]} {
			run file delete $sub
		    }
		}
	    } else {
		if {![string match $pattern $base]} {continue}
		xcopyfile $file $sub
	    }
	}
    }
}

proc get_input {f} {return [read [set if [open $f r]]][close $if]}
proc write_out {f text} {
    global config
    if {$config(dry)} {log "Generate $f" ; return}
    catch {file delete -force $f}
    puts -nonewline [set of [open $f w]] $text
    close $of
}


# --------------------------------------------------------------
# Use configuration to perform installation

proc clear {}     {global message ; set     message ""}
proc msg   {text} {global message ; append  message $text \n ; return}
proc get   {}     {global message ; return $message}

proc log {text} {
    global config
    if {!$config(gui)} {puts stdout $text ; flush stdout ; return}
    .l.t insert end $text\n
    .l.t see    end
    update
    return
}
proc log* {text} {
    global config
    if {!$config(gui)} {puts -nonewline stdout $text ; flush stdout ; return}
    .l.t insert end $text
    .l.t see    end
    update
    return
}

proc run {args} {
    global config
    if {$config(dry)} {
	log [join $args]
	return
    }
    if {[catch {eval $args} msg]} {
        if {$config(gui)} {
            installErrorMsgBox $msg
        } else {
            return -code error "Install error:\n $msg" 
        }
    }
    log* .
    return
}

proc xinstall {type args} {
    global modules guide
    foreach m $modules {
	eval $guide($m,$type) $m $args
    }
    return
}

proc ainstall {} {
    global apps config tcl_platform distribution

    if {[string compare $tcl_platform(platform) windows] == 0} {
	set ext .tcl
    } else {
	set ext ""
    }

    foreach a $apps {
	set aexe [file join $distribution apps $a]
	set adst [file join $config(app,path) ${a}$ext]

	log "\nGenerating $adst"
	if {!$config(dry)} {
	    file mkdir [file dirname  $adst]
	    catch {file delete -force $adst}
	    file copy -force $aexe    $adst
	}
    }
    return
}

proc doinstall {} {
    global config package_version distribution package_name modules excluded

    if {!$config(no-exclude)} {
	foreach p $excluded {
	    set pos [lsearch -exact $modules $p]
	    if {$pos < 0} {continue}
	    set modules [lreplace $modules $pos $pos]
	}
    }

    if {$config(doc,nroff)} {
	set config(man.macros) [string trim [get_input \
		[file join $distribution support installation man.macros]]]
    }
    if {$config(pkg)}       {
	xinstall   pkg $config(pkg,path)
	gen_main_index $config(pkg,path) $package_name $package_version
    }
    if {$config(doc,nroff)} {
	foreach dir [glob -directory $distribution/embedded/man/files/modules *] {
	    xcopy $dir $config(doc,nroff,path) 1
	}
	xcopy $distribution/embedded/man/files/apps $config(doc,nroff,path) 1
    }
    if {$config(doc,html)}  {
	#xinstall doc html  html $config(doc,html,path)
	xcopy $distribution/embedded/www $config(doc,html,path) 1
    }
    if {$config(exa)}       {xinstall exa $config(exa,path)}
    if {$config(app)}       {ainstall}
    log ""
    return
}


# --------------------------------------------------------------
# Initialize configuration.

array set config {
    pkg 1 pkg,path {}
    app 1 app,path {}
    doc,nroff 0 doc,nroff,path {}
    doc,html  0 doc,html,path  {}
    exa 1 exa,path {}
    dry 0 wait 1 valid 1
    gui 0 no-gui 0 no-exclude 0
}

# --------------------------------------------------------------
# Determine a default configuration, if possible

proc defaults {} {
    global tcl_platform config package_version package_name distribution

    if {[string compare $distribution [info nameofexecutable]] == 0} {
	# Starpack. No defaults for location.
    } else {
	# Starkit, or unwrapped. Derive defaults location from the
	# location of the executable running the installer, or the
	# location of its library.

	# For a starkit [info library] is inside the running
	# tclkit. Detect this and derive the lcoation from the
	# location of the executable itself for that case.

	if {[string match [info nameofexecutable]* [info library]]} {
	    # Starkit
	    set libdir [file join [file dirname [file dirname [info nameofexecutable]]] lib]
	} else {
	    # Unwrapped.
	    if {[catch {set libdir [lindex $::tcl_pkgPath end]}]} {
		set libdir [file dirname [info library]]
	    }
	}

	set basedir [file dirname $libdir]
	set bindir  [file join $basedir bin]

	if {[string compare $tcl_platform(platform) windows] == 0} {
	    set mandir  {}
	    set htmldir [file join $basedir ${package_name}_doc]
	} else {
	    set mandir  [file join $basedir man mann]
	    set htmldir [file join $libdir  ${package_name}${package_version} ${package_name}_doc]
	}

	set config(app,path)       $bindir
	set config(pkg,path)       [file join $libdir ${package_name}${package_version}]
	set config(doc,nroff,path) $mandir
	set config(doc,html,path)  $htmldir
	set config(exa,path)       [file join $bindir ${package_name}_examples${package_version}]
    }

    if {[string compare $tcl_platform(platform) windows] == 0} {
	set config(doc,nroff) 0
	set config(doc,html)  1
    } else {
	set config(doc,nroff) 1
	set config(doc,html)  0
    }
    return
}

# --------------------------------------------------------------
# Show configuration on stdout.

proc showpath {prefix key} {
    global config

    if {$config($key)} {
	if {[string length $config($key,path)] == 0} {
	    puts "${prefix}Empty path, invalid."
	    set config(valid) 0
	    msg "Invalid path: [string trim $prefix " 	:"]"
	} else {
	    puts "${prefix}$config($key,path)"
	}
    } else {
	puts "${prefix}Not installed."
    }
}

proc showconfiguration {} {
    global config package_version package_name_cap

    puts "Installing $package_name_cap $package_version"
    if {$config(dry)} {
	puts "\tDry run, simulation, no actual activity."
	puts ""
    }

    puts "You have chosen the following configuration ..."
    puts ""

    showpath "Packages:      " pkg
    #showpath "Applications:  " app
    showpath "Examples:      " exa

    if {$config(doc,nroff) || $config(doc,html)} {
	puts "Documentation:"
	puts ""

	showpath "\tNROFF:  " doc,nroff
	showpath "\tHTML:   " doc,html
    } else {
	puts "Documentation: Not installed."
    }
    puts ""
    return
}

# --------------------------------------------------------------
# Setup the installer user interface

proc browse {label key} {
    global config

    set  initial $config($key)
    if {$initial == {}} {set initial [pwd]}

    set dir [tk_chooseDirectory \
	    -title    "Select directory for $label" \
	    -parent    . \
	    -initialdir $initial \
	    ]

    if {$dir == {}} {return} ; # Cancellation

    set config($key)  $dir
    return
}

proc setupgui {} {
    global config package_name_cap package_version
    set config(gui) 1

    wm withdraw .
    wm title . "Installing $package_name_cap $package_version"

    # .app checkbutton 1 0 1 {-anchor w -text {Applications:} -variable config(app)}
    # .appe entry 1 1 1 {-width 40 -textvariable config(app,path)}
    # .appb button 1 2 1 {-text ... -command {browse Applications app,path}}
    foreach {w type cspan col row opts} {
	.pkg checkbutton 1 0 0 {-anchor w -text {Packages:}     -variable config(pkg)}
	.dnr checkbutton 1 0 1 {-anchor w -text {Doc. Nroff:}   -variable config(doc,nroff)}
	.dht checkbutton 1 0 2 {-anchor w -text {Doc. HTML:}    -variable config(doc,html)}
	.exa checkbutton 1 0 3 {-anchor w -text {Examples:}     -variable config(exa)}

	.spa frame  3 0 4 {-bg black -height 2}

	.dry checkbutton 2 0 6 {-anchor w -text {Simulate installation} -variable config(dry)}

	.pkge entry 1 1 0 {-width 40 -textvariable config(pkg,path)}
	.dnre entry 1 1 1 {-width 40 -textvariable config(doc,nroff,path)}
	.dhte entry 1 1 2 {-width 40 -textvariable config(doc,html,path)}
	.exae entry 1 1 3 {-width 40 -textvariable config(exa,path)}

	.pkgb button 1 2 0 {-text ... -command {browse Packages     pkg,path}}
	.dnrb button 1 2 1 {-text ... -command {browse Nroff        doc,nroff,path}}
	.dhtb button 1 2 2 {-text ... -command {browse HTML         doc,html,path}}
	.exab button 1 2 3 {-text ... -command {browse Examples     exa,path}}

	.sep  frame  3 0 7 {-bg black -height 2}

	.run  button 1 0 8 {-text {Install} -command {set ::run 1}}
	.can  button 1 1 8 {-text {Cancel}  -command {exit}}
    } {
	eval [list $type $w] $opts
	grid $w -column $col -row $row -sticky ew -columnspan $cspan
	grid rowconfigure . $row -weight 0
    }

    grid .can -sticky e

    grid rowconfigure    . 9 -weight 1
    grid columnconfigure . 0 -weight 0
    grid columnconfigure . 1 -weight 1

    wm deiconify .
    return
}

proc handlegui {} {
    setupgui
    vwait ::run
    showconfiguration
    validate

    toplevel .l
    wm title .l "Install log"
    text     .l.t -width 70 -height 25 -relief sunken -bd 2
    pack     .l.t -expand 1 -fill both

    return
}

# --------------------------------------------------------------
# Handle a command line

proc handlecmdline {} {
    showconfiguration
    validate
    wait
    return
}

proc processargs {} {
    global argv argv0 config

    while {[llength $argv] > 0} {
	switch -exact -- [lindex $argv 0] {
	    +excluded    {set config(no-exclude) 1}
	    -no-wait     {set config(wait) 0}
	    -no-gui      {set config(no-gui) 1}
	    -simulate    -
	    -dry-run     {set config(dry) 1}
	    -html        {set config(doc,html) 1}
	    -nroff       {set config(doc,nroff) 1}
	    -examples    {set config(exa) 1}
	    -pkgs        {set config(pkg) 1}
	    -apps        {set config(app) 1}
	    -no-html     {set config(doc,html) 0}
	    -no-nroff    {set config(doc,nroff) 0}
	    -no-examples {set config(exa) 0}
	    -no-pkgs     {set config(pkg) 0}
	    -no-apps     {set config(app) 0}
	    -pkg-path {
		set config(pkg) 1
		set config(pkg,path) [lindex $argv 1]
		set argv             [lrange $argv 1 end]
	    }
	    -app-path {
		set config(app) 1
		set config(app,path) [lindex $argv 1]
		set argv             [lrange $argv 1 end]
	    }
	    -nroff-path {
		set config(doc,nroff) 1
		set config(doc,nroff,path) [lindex $argv 1]
		set argv                   [lrange $argv 1 end]
	    }
	    -html-path {
		set config(doc,html) 1
		set config(doc,html,path) [lindex $argv 1]
		set argv                  [lrange $argv 1 end]
	    }
	    -example-path {
		set config(exa) 1
		set config(exa,path) [lindex $argv 1]
		set argv             [lrange $argv 1 end]
	    }
	    -help   -
	    default {
		puts stderr "usage: $argv0 ?-dry-run/-simulate? ?-no-wait? ?-no-gui? ?-html|-no-html? ?-nroff|-no-nroff? ?-examples|-no-examples? ?-pkgs|-no-pkgs? ?-pkg-path path? ?-apps|-no-apps? ?-app-path path? ?-nroff-path path? ?-html-path path? ?-example-path path?"
		exit 1
	    }
	}
	set argv [lrange $argv 1 end]
    }
    return
}

proc validate {} {
   global config

    if {$config(valid)} {return}

    puts "Invalid configuration detected, aborting."
    puts ""
    puts "Please use the option -help to get more information"
    puts ""

    if {$config(gui)} {
	tk_messageBox \
		-icon error -type ok \
		-default ok \
		-title "Illegal configuration" \
		-parent . -message [get]
	clear
    }
    exit 1
}

proc installErrorMsgBox {msg} {
    tk_messageBox \
	    -icon error -type ok \
	    -default ok \
	    -title "Install error" \
	    -parent . -message $msg
    exit 1
}

proc wait {} {
   global config

    if {!$config(wait)} {return}

    puts -nonewline stdout "Is the chosen configuration ok ? y/N: "
    flush stdout
    set answer [gets stdin]
    if {($answer == {}) || [string match "\[Nn\]*" $answer]} {
	puts stdout "\tNo. Aborting."
	puts stdout ""
	exit 0
    }
    return
}

# --------------------------------------------------------------
# Main code

proc main {} {
    global config

    defaults
    processargs
    if {$config(no-gui) || [catch {package require Tk}]} {
	handlecmdline
    } else {
	handlegui
    }
    doinstall
    return
}

# --------------------------------------------------------------
if {[catch {
    main
}]} {
    puts $errorInfo
}
exit 0
# --------------------------------------------------------------
