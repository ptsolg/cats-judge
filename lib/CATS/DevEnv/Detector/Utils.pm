package CATS::DevEnv::Detector::Utils;
use strict;
use warnings;
use if $^O eq 'MSWin32', "Win32::TieRegistry";
use if $^O eq 'MSWin32', "Win32API::File" => qw(getLogicalDrives);

use File::Spec;
use File::Path qw(remove_tree);
use constant FS => 'File::Spec';
use constant DIRS_IN_PATH => FS->path();

use parent qw(Exporter);
use vars qw(@EXPORT);
@EXPORT = qw(write_file version_cmp clear
    which env_path folder registry registry_loop program_files drives
);

sub clear {
    my ($ret) = @_;
    remove_tree("tmp");
    return $ret;
}

sub write_file {
    my ($name, $text) = @_;
    if ( !-d "tmp" ) {
        mkdir "tmp";
    }
    my $file = FS->catfile("tmp", $name);
    open(my $fh, '>', $file);
    print $fh $text;
    close $fh;
    return $file;
}


sub which {
    my ($detector, $file) = @_;
    if ($^O eq "MSWin32") {
        return 0;
    }
    my $output =`which $file`;
    for my $line (split /\n/, $output) {
        $detector->validate_and_add($line);
    }
}

sub env_path {
    my ($detector, $file) = @_;
    for my $dir (DIRS_IN_PATH) {
        folder($detector, $dir, $file);
    }
}

sub extension {
    my ($detector, $path) = @_;
    my @exts = ('', '.exe', '.bat', '.com');
    for my $e (@exts) {
        $detector->validate_and_add($path . $e);
    }
}

sub folder {
    my ($detector, $folder, $file) = @_;
    my $path = FS->catfile($folder, $file);
    extension($detector, $path);
}

use constant REGISTRY_SUFFIX => qw(
    HKEY_LOCAL_MACHINE/SOFTWARE/
    HKEY_LOCAL_MACHINE/SOFTWARE/Wow6432Node/
);

sub _registry {
    my ($detector, $reg, $key, $local_path, $file) = @_;
    my $registry = get_registry_obj($detector, $reg) or return 0;
    my $folder = $registry->GetValue($key) or return 0;
    folder($detector, FS->catdir($folder,$local_path) , $file);
}

sub registry {
    my ($detector, $reg, $key, $local_path, $file) = @_;
    $local_path ||= "";
    for my $reg_suffix (REGISTRY_SUFFIX) {
        _registry($detector, $reg_suffix . $reg, $key, $local_path, $file);    
    }
}

sub get_registry_obj {
    my ($detector, $reg) = @_;
    return Win32::TieRegistry->new($reg, {
        Access => Win32::TieRegistry::KEY_READ(),
        Delimiter => '/'
    });
}

sub registry_loop {
    my ($detector, $reg, $key, $local_path, $file) = @_;
    $local_path ||= "";
    for my $reg_suffix (REGISTRY_SUFFIX) {
        my $registry = get_registry_obj($detector, $reg_suffix . $reg) or return 0;
        for my $subkey ($registry->SubKeyNames()) {
            my $subreg = $registry->Open($subkey, {
                Access => Win32::TieRegistry::KEY_READ(),
                Delimiter => '/'
            });
            my $r = $subreg->Open($key);
            my $folder = $subreg->GetValue($key) or ($r && $r->GetValue("")) or next; 
            folder($detector, FS->catdir($folder, $local_path), $file);
        }
    }
}

sub program_files {
    my ($detector, $local_path, $file) = @_;
    my @keys = (
        'ProgramFilesDir',
        'ProgramFilesDir (x86)'
    );
    foreach my $key (@keys) {
        registry($detector, "Microsoft/Windows/CurrentVersion", $key, $file, $local_path);
    }
}


sub drives {
    my ($detector, $folder, $file) = @_;
    $folder ||= "";
    my @drives = getLogicalDrives();
    foreach my $drive (@drives) {
        folder($detector, FS->catdir($drive, $folder), $file);
    }
}

sub version_cmp {
    my ($a, $b) = @_;
    my @A = ($a =~ /([-.]|\d+|[^-.\d]+)/g);
    my @B = ($b =~ /([-.]|\d+|[^-.\d]+)/g);

    my ($A, $B);
    while (@A and @B) {
	$A = shift @A;
	$B = shift @B;
	if ($A eq '.' and $B eq '.') {
	    next;
	} elsif ( $A eq '.' ) {
	    return -1;
	} elsif ( $B eq '.' ) {
	    return 1;
	} elsif ($A =~ /^\d+$/ and $B =~ /^\d+$/) {
	    if ($A =~ /^0/ || $B =~ /^0/) {
		return $A cmp $B if $A cmp $B;
	    } else {
		return $A <=> $B if $A <=> $B;
	    }
	} else {
	    $A = uc $A;
	    $B = uc $B;
	    return $A cmp $B if $A cmp $B;
	}
    }
    @A <=> @B;
}

1;
