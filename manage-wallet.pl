#!/usr/bin/perl -w
use strict;
use File::Copy;

my $ACTIVE_WALLET_LOCATION = '/Users/scsibug/Library/Application Support/Bitcoin/wallet.dat';
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

my $num_args = $#ARGV+1;
if ($num_args == 1 && $ARGV[0] eq "backup") {
    print "backing up current wallet from $ACTIVE_WALLET_LOCATION\n";
    # find the alias for the current wallet
    my $current_alias;
    $current_alias = `xattr -p btc-wallet-alias '$ACTIVE_WALLET_LOCATION'`;
    chomp($current_alias);
    if ($? == 0) {
        # alias was found
        # don't do any work if the md5 hashes of both wallets match.
        my $active_wallet_md5 = `md5 -q '$ACTIVE_WALLET_LOCATION'`;
        my $backup_wallet_md5 = `md5 -q '${BACKUP_GIT_REPO}/${current_alias}.dat'`;
        if ($active_wallet_md5 eq $backup_wallet_md5) {
            print "No change in wallet from backup, exiting.\n";
            exit(0);
        } else {
            print "$active_wallet_md5 != $backup_wallet_md5\n";
        }
    } else {
        print "\nIt looks like this wallet has not been backed up yet.  Please enter an alias for the wallet, and press enter\n";
        $current_alias = <STDIN>;
        chomp($current_alias);
        # save alias as an attribute on the wallet
        `xattr -w btc-wallet-alias $current_alias $ACTIVE_WALLET_LOCATION`;
    } 

    print "wallet alias is $current_alias end\n";
    print "Saving wallet with alias $current_alias\n";
    # copy from active wallet to repo
    print "copying from $ACTIVE_WALLET_LOCATION to ${BACKUP_GIT_REPO}/${current_alias}.dat\n";
    my $ret = copy($ACTIVE_WALLET_LOCATION, "${BACKUP_GIT_REPO}/${current_alias}.dat")  or die "Copy failed: $!";

    
} elsif ($num_args == 2 && $ARGV[0] eq "restore") {
    print "restoring wallet $ARGV[1]";
} else {
    print $USAGE;
}
