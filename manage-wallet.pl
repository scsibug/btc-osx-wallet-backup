#!/usr/bin/perl -w
#####################################################
#
# Copyright 2011 Greg Heartsfield <scsibug@imap.cc>
# BSD-3 Licensed (see accompanying LICENSE file)
#
# Useful? tip 1KgeamVRTrU8DaBLRU2tv6VruwV9BRWDkm
#
# Instructions:
#  Create a git repo, and reference it below in
#  $BACKUP_GIT_REPO.  Run this program to see
#  usage information.  Generally, the first thing
#  you'll want to do is run the 'backup' command to
#  save a wallet in the git repo.
#
#####################################################
use strict;
use File::Copy;
use Fcntl qw(:flock);
use Env qw(HOME);

#####################################################
# User-modifiable environment data

# Where is your bitcoin data directory?
my $BITCOIN_DATA_DIR = "$HOME/Library/Application Support/Bitcoin/";
my $ACTIVE_WALLET_LOCATION = $BITCOIN_DATA_DIR.'wallet.dat';
# this should be an init'd git repo.
my $BACKUP_GIT_REPO = "$HOME/Documents/BTC_repo";

#####################################################
# Main program

my $USAGE = <<'END';
==== Bitcoin Wallet Management ====
USAGE:
 Determine which wallet is currently active
   $ manage-wallet.pl show
 Backing up a wallet to the repository:
   $ manage-wallet.pl backup
     (If you have never backed up this wallet, you will be prompted for a name.)
 Activating a wallet for use with Bitcoin:
   $ manage-wallet.pl activate wallet-name
     (If the current wallet has changed, you will be prompted to save/commit it.)
 Creating a new wallet (UNIMPLEMENTED):
   $ manage-wallet.pl create
     (This backs up the existing wallet, and then deletes the original.)
END

### Some preliminary checks...
# Make sure bitcoin client ins't running
&get_wallet_lock() or die  "Bitcoin must be shutdown before running this script.\n";

# Make sure this OS supports xattr (OS X only?)
if (!&is_xattr_available()) {
    die "This script requires the xattr command be available.\n";
}

# Verify backup directory is a valid git repo
if (!&is_git_repo($BACKUP_GIT_REPO)) {
    die "$BACKUP_GIT_REPO is not a git repository.";
}

my $num_args = $#ARGV+1;
my $current_alias;
if ($num_args == 1 && $ARGV[0] eq "show") {
    &cmd_show();
} elsif ($num_args == 1 && $ARGV[0] eq "backup") {
    &cmd_backup();
} elsif ($num_args == 2 && $ARGV[0] eq "activate") {
    &cmd_activate($ARGV[1]);
} else {
    print $USAGE;
}


#####################################################
# Subroutines


sub cmd_show() {
    my $current_alias;
    eval {
        $current_alias = &current_wallet();
    };
    if ($@) {
        print "The current wallet did not originate in the backup repository.";
        return;
    }
    print "Current wallet: $current_alias.\n";
    if (-e "${BACKUP_GIT_REPO}/${current_alias}.dat") {
        my $wallets_match = &do_files_match($ACTIVE_WALLET_LOCATION, "${BACKUP_GIT_REPO}/${current_alias}.dat");
        if ($wallets_match) {
            print "\tNo difference between active and backup wallet.\n";
        } else {
            print "\tActive wallet has outstanding changes NOT in backup.\n";
        }
    } else {
        die "Error: alias \"${current_alias}\" does not exist in the backup repository.\n";
    }
    print "All wallet aliases:\n";
    print "\t".join(", ", &all_wallets())."\n";
}

sub cmd_backup() {
    print "Backing up current wallet from $ACTIVE_WALLET_LOCATION\n";
    my $current_alias;
    eval {
        $current_alias = &current_wallet();
    };
    if (!$@) {
        # don't do any work if the md5 hashes of both wallets match.
        my $wallets_match = &do_files_match($ACTIVE_WALLET_LOCATION, "${BACKUP_GIT_REPO}/${current_alias}.dat");
        if ($wallets_match) {
            print "No change in wallet from backup, exiting.\n";
            exit(0);
        }
    } else {
        print "\nIt looks like this wallet has not been backed up yet.  Please enter an alias for the wallet, and press enter\n";
        $current_alias = <STDIN>;
        chomp($current_alias);
        # save alias as an attribute on the wallet
        `xattr -w btc-wallet-alias $current_alias '$ACTIVE_WALLET_LOCATION'`;
    }
    print "Saving wallet with alias \"$current_alias\"\n";
    # copy from active wallet to repo
    print "copying from $ACTIVE_WALLET_LOCATION to ${BACKUP_GIT_REPO}/${current_alias}.dat\n";
    copy($ACTIVE_WALLET_LOCATION, "${BACKUP_GIT_REPO}/${current_alias}.dat")  or die "Copy failed: $!";
    # run git add/commit
    chdir($BACKUP_GIT_REPO);
    `git add ${current_alias}.dat`;
    print `git commit ${current_alias}.dat -m 'Automatic wallet backup for ${current_alias}.'`;
}

sub cmd_activate($) {
    my($desired_alias) = @_;
    print "activating wallet $desired_alias to $ACTIVE_WALLET_LOCATION\n";
    # TODO: verify desired alias exists in repo
    if (-e "${BACKUP_GIT_REPO}/${desired_alias}.dat") {
        # TODO: make sure that the current wallet is backed up (md5 sum of active and backup wallet match) before overwriting
        # copy wallet with desired alias to the active wallet location
        copy("${BACKUP_GIT_REPO}/${desired_alias}.dat", $ACTIVE_WALLET_LOCATION)  or die "Copy failed: $!";
        # set file attribute with alias so we can recognize which wallet it is for other commands
        `xattr -w btc-wallet-alias '$desired_alias' '$ACTIVE_WALLET_LOCATION'`;
    } else {
        print "Alias \"${desired_alias}\" does not exist in the backup repository.\n";
        exit(1);
    }
}

# given two filenames, return 1 if files match (md5 hash), 0 otherwise.
sub do_files_match($$) {
    my($a, $b) = @_;
    my $a_md5 = `md5 -q '$a'`;
    my $b_md5 = `md5 -q '$b'`;
    return ($a_md5 eq $b_md5);
}

# If we got a lock on the bitcoin data dir, return true.
# we hold onto this for the duration of the program.
sub get_wallet_lock() {
    my $lockfile = $BITCOIN_DATA_DIR.'.lock';
    open(LOCKFILE, ">>", $lockfile)
        or return 0;
    flock(LOCKFILE, LOCK_NB|LOCK_EX) or return 0;
    return 1;
}

# Check platform... if we don't have xattr available
sub is_xattr_available() {
    `which -s xattr`;
    if ($?) {
        return 0;
    } else {
        return 1;
    }
}

sub is_git_repo($) {
    my ($gitrepo) = @_;
    if (-e "${gitrepo}/.git") {
        return 1;
    } else {
        return 0;
    }
}

# Return the name of the currently active wallet
sub current_wallet() {
    my $current_alias = `xattr -p btc-wallet-alias '$ACTIVE_WALLET_LOCATION'`;
    if ($?) {
        die "Could not get currently active wallet name.";
    }
    chomp($current_alias);
    return $current_alias;
}

sub all_wallets() {
     my @wallet_paths = <$BACKUP_GIT_REPO/*.dat>;
     my @wallet_aliases = ();
     foreach my $alias (@wallet_paths) {
         $alias =~ s/.*\///; #strip off all but filename
         $alias =~ s/\.dat//; #strip extension
         push(@wallet_aliases,$alias);
     }
     return @wallet_aliases;
}
