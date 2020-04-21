#!/usr/bin/perl -I/home/phil/perl/cpan/GitHubCrud/lib
#-------------------------------------------------------------------------------
# Upload the the folders specified on the command line to GitHub from a workflow
# Philip R Brenan at gmail dot com, Appa Apps Ltd, 2020
#-------------------------------------------------------------------------------
use warnings FATAL => qw(all);
use strict;
use Data::Table::Text qw(:all);
use GitHub::Crud;

my $userRepo = $ENV{GITHUB_REPOSITORY};                                         # Repository to load to
$userRepo or die 'Cannot find environment variable: $GITHUB_REPOSITORY';

my $token    = $ENV{token};                                                     # Access token
$token or die 'Cannot find token';

lll "Upload folders to $userRepo";

my $folders;                                                                    # Number of folders uploaded

for my $folder(@ARGV)                                                           # Upload each folder specified on the command line
 {lll $folder;
  unless(-d $folder)
   {lll "No such folder: $folder";
    next;
   }
  my ($u, $r) = split m(/), $userRepo, 2;
  GitHub::Crud::writeFolderUsingSavedToken  $u, $r, $folder, $folder, $token;   # Upload folder to repo using token
  ++$folders
 }

say STDERR "$folders uploaded";                                                 # Summary of results
