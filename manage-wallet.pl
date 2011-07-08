#!/usr/bin/perl -w
#####################################################
#
# Copyright 2011 Greg Heartsfield <scsibug@imap.cc>
# BSD-3 Licensed (see accompanying LICENSE file)
#
# Useful? tip 1KgeamVRTrU8DaBLRU2tv6VruwV9BRWDkm
#####################################################

use strict;
use File::Copy;

my $BITCOIN_DATA_DIR = '/Users/scsibug/Library/Application Support/Bitcoin/';
my $ACTIVE_WALLET_LOCATION = $BITCOIN_DATA_DIR.'wallet.dat';
# this should be an init'd git repo.
my $BACKUP_GIT_REPO = "/Users/scsibug/testing_repo";

my $USAGE = <<END;
==== Bitcoin Wallet Management ====
USAGE:
 Backing up a wallet to the repository:
   manage-wallet.pl backup
     (If you have never backed up this wallet, you will be prompted for a name.)
 Activating a wallet for use with Bitcoin:
   manage-wallet.pl activate wallet-name
     (If the current wallet has changed, you will be prompted to save/commit it.)
END

# Make sure bitcoin client ins't running
if (&is_bitcoin_running()) {
    print "Bitcoin must be shutdown before running this script.\n";
    exit(1);
}
# Make sure this OS supports xattr (OS X only?)
if (!&is_xattr_available()) {
    print "This script requires the xattr command be available.\n";
}
my $num_args = $#ARGV+1;
my $current_alias;
if ($num_args == 1 && $ARGV[0] eq "show") {
    $current_alias = `xattr -p btc-wallet-alias '$ACTIVE_WALLET_LOCATION'`;
    chomp($current_alias);
    if ($? == 0) {
        # alias was found
        print "Current wallet in use is \"$current_alias\".\n";
    }
    if (-e "${BACKUP_GIT_REPO}/${current_alias}.dat") {
        my $wallets_match = &do_files_match($ACTIVE_WALLET_LOCATION, "${BACKUP_GIT_REPO}/${current_alias}.dat");
        if ($wallets_match) {
            print "\tNo differences between active and backup wallets.\n";
        } else {
            print "\tActive wallet has outstanding changes NOT in backup.\n";
        }
    } else {
        print "Error: alias \"${current_alias}\" does not exist in the backup repository.\n";
        exit(1);
    }
} elsif ($num_args == 1 && $ARGV[0] eq "backup") {
    print "Backing up current wallet from $ACTIVE_WALLET_LOCATION\n";
    # find the alias for the current wallet
    $current_alias = `xattr -p btc-wallet-alias '$ACTIVE_WALLET_LOCATION'`;
    chomp($current_alias);
    if ($? == 0) {
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
        `xattr -w btc-wallet-alias $current_alias $ACTIVE_WALLET_LOCATION`;
    } 
    print "Saving wallet with alias \"$current_alias\"\n";
    # copy from active wallet to repo
    print "copying from $ACTIVE_WALLET_LOCATION to ${BACKUP_GIT_REPO}/${current_alias}.dat\n";
    copy($ACTIVE_WALLET_LOCATION, "${BACKUP_GIT_REPO}/${current_alias}.dat")  or die "Copy failed: $!";
    # run git add/commit
    chdir($BACKUP_GIT_REPO);
    `git add ${current_alias}.dat`;
    `git commit ${current_alias}.dat -m 'Automatic wallet backup for ${current_alias}.'`;
} elsif ($num_args == 2 && $ARGV[0] eq "activate") {
    my $desired_alias = $ARGV[1];
    print "activating wallet $ARGV[1] to $ACTIVE_WALLET_LOCATION\n";
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
} else {
    print $USAGE;
}

# given two filenames, return 1 if files match (md5 hash), 0 otherwise.
sub do_files_match($$) {
    my($a, $b) = @_;
    my $a_md5 = `md5 -q '$a'`;
    my $b_md5 = `md5 -q '$b'`;
    return ($a_md5 eq $b_md5);
}

# If bitcoin is running, return true.
sub is_bitcoin_running() {
    return (-e $BITCOIN_DATA_DIR.'.lock');
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
