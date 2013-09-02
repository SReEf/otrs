# --
# Kernel/System/CustomerAuth/LDAP.pm - provides the ldap authentication
# Copyright (C) 2001-2013 OTRS AG, http://otrs.com/
# --
# $Id: LDAP.pm,v 1.38.2.1 2012-08-21 08:41:41 mg Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::CustomerAuth::LDAP;

use strict;
use warnings;

use Net::LDAP;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.38.2.1 $) [1];

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for (qw(LogObject ConfigObject DBObject EncodeObject)) {
        $Self->{$_} = $Param{$_} || die "No $_!";
    }

    # Debug 0=off 1=on
    $Self->{Debug} = 0;

    # get ldap preferences
    $Self->{Die} = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::Die' . $Param{Count} );
    if ( $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::Host' . $Param{Count} ) ) {
        $Self->{Host}
            = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::Host' . $Param{Count} );
    }
    else {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Need Customer::AuthModule::LDAPHost$Param{Count} in Kernel/Config.pm",
        );
        return;
    }
    if (
        defined(
            $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::BaseDN' . $Param{Count} )
        )
        )
    {
        $Self->{BaseDN}
            = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::BaseDN' . $Param{Count} );
    }
    else {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Need Customer::AuthModule::LDAPBaseDN$Param{Count} in Kernel/Config.pm",
        );
        return;
    }
    if ( $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::UID' . $Param{Count} ) ) {
        $Self->{UID}
            = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::UID' . $Param{Count} );
    }
    else {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Need 'Customer::AuthModule::LDAP::UID$Param{Count} in Kernel/Config.pm",
        );
        return;
    }
    $Self->{SearchUserDN}
        = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::SearchUserDN' . $Param{Count} )
        || '';
    $Self->{SearchUserPw}
        = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::SearchUserPw' . $Param{Count} )
        || '';
    $Self->{GroupDN}
        = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::GroupDN' . $Param{Count} ) || '';
    $Self->{AccessAttr}
        = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::AccessAttr' . $Param{Count} )
        || '';
    $Self->{UserAttr}
        = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::UserAttr' . $Param{Count} )
        || 'DN';
    $Self->{UserSuffix}
        = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::UserSuffix' . $Param{Count} )
        || '';
    $Self->{DestCharset}
        = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::Charset' . $Param{Count} )
        || 'utf-8';

    # ldap filter always used
    $Self->{AlwaysFilter}
        = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::AlwaysFilter' . $Param{Count} )
        || '';

    # Net::LDAP new params
    if ( $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::Params' . $Param{Count} ) ) {
        $Self->{Params}
            = $Self->{ConfigObject}->Get( 'Customer::AuthModule::LDAP::Params' . $Param{Count} );
    }
    else {
        $Self->{Params} = {};
    }

    return $Self;
}

sub GetOption {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{What} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => "Need What!" );
        return;
    }

    # module options
    my %Option = ( PreAuth => 0, );

    # return option
    return $Option{ $Param{What} };
}

sub Auth {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(User Pw)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_!" );
            return;
        }
    }
    $Param{User} = $Self->_ConvertTo( $Param{User}, 'utf-8' );
    $Param{Pw}   = $Self->_ConvertTo( $Param{Pw},   'utf-8' );

    # get params
    my $RemoteAddr = $ENV{REMOTE_ADDR} || 'Got no REMOTE_ADDR env!';

    # remove leading and trailing spaces
    $Param{User} =~ s/^\s+//;
    $Param{User} =~ s/\s+$//;

    # add user suffix
    if ( $Self->{UserSuffix} ) {
        $Param{User} .= $Self->{UserSuffix};

        # just in case for debug
        if ( $Self->{Debug} > 0 ) {
            $Self->{LogObject}->Log(
                Priority => 'notice',
                Message  => "CustomerUser: ($Param{User}) added $Self->{UserSuffix} to username!",
            );
        }
    }

    # just in case for debug!
    if ( $Self->{Debug} > 0 ) {
        $Self->{LogObject}->Log(
            Priority => 'notice',
            Message => "CustomerUser: '$Param{User}' tried to authentificate with Pw: '$Param{Pw}' "
                . "(REMOTE_ADDR: $RemoteAddr)",
        );
    }

    # ldap connect and bind (maybe with SearchUserDN and SearchUserPw)
    my $LDAP = Net::LDAP->new( $Self->{Host}, %{ $Self->{Params} } );
    if ( !$LDAP ) {
        if ( $Self->{Die} ) {
            die "Can't connect to $Self->{Host}: $@";
        }
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Can't connect to $Self->{Host}: $@",
        );
        return;
    }
    my $Result = '';
    if ( $Self->{SearchUserDN} && $Self->{SearchUserPw} ) {
        $Result = $LDAP->bind( dn => $Self->{SearchUserDN}, password => $Self->{SearchUserPw} );
    }
    else {
        $Result = $LDAP->bind();
    }
    if ( $Result->code ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => 'First bind failed! ' . $Result->error(),
        );
        return;
    }

    # user quote
    my $UserQuote = $Param{User};
    $UserQuote =~ s/\\/\\\\/g;
    $UserQuote =~ s/\(/\\(/g;
    $UserQuote =~ s/\)/\\)/g;

    # build filter
    my $Filter = "($Self->{UID}=$UserQuote)";

    # prepare filter
    if ( $Self->{AlwaysFilter} ) {
        $Filter = "(&$Filter$Self->{AlwaysFilter})";
    }

    # perform user search
    $Result = $LDAP->search(
        base   => $Self->{BaseDN},
        filter => $Filter,
        attrs  => ['1.1'],
    );
    if ( $Result->code ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => 'Search failed! ' . $Result->error,
        );
        $LDAP->disconnect;
        return;
    }

    # get whole user dn
    my $UserDN = '';
    for my $Entry ( $Result->all_entries ) {
        $UserDN = $Entry->dn();
    }

    # log if there is no LDAP user entry
    if ( !$UserDN ) {

        # failed login note
        $Self->{LogObject}->Log(
            Priority => 'notice',
            Message  => "CustomerUser: $Param{User} authentication failed, no LDAP entry found!"
                . "BaseDN='$Self->{BaseDN}', Filter='$Filter', (REMOTE_ADDR: $RemoteAddr).",
        );

        # take down session
        $LDAP->unbind;
        $LDAP->disconnect;
        return;
    }

    # DN quote
    my $UserDNQuote = $UserDN;
    $UserDNQuote =~ s/\\/\\\\/g;
    $UserDNQuote =~ s/\(/\\(/g;
    $UserDNQuote =~ s/\)/\\)/g;

    # check if user need to be in a group!
    if ( $Self->{AccessAttr} && $Self->{GroupDN} ) {

        # just in case for debug
        if ( $Self->{Debug} > 0 ) {
            $Self->{LogObject}->Log(
                Priority => 'notice',
                Message  => 'check for groupdn!',
            );
        }

        # search if we're allowed to
        my $Filter2 = '';
        if ( $Self->{UserAttr} eq 'DN' ) {
            $Filter2 = "($Self->{AccessAttr}=$UserDNQuote)";
        }
        else {
            $Filter2 = "($Self->{AccessAttr}=$UserQuote)";
        }
        my $Result2 = $LDAP->search(
            base   => $Self->{GroupDN},
            filter => $Filter2,
            attrs  => ['1.1'],
        );
        if ( $Result2->code ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Search failed! base='$Self->{GroupDN}', filter='$Filter2', "
                    . $Result2->error,
            );
            $LDAP->unbind;
            $LDAP->disconnect;
            return;
        }

        # extract it
        my $GroupDN = '';
        for my $Entry ( $Result2->all_entries ) {
            $GroupDN = $Entry->dn();
        }

        # log if there is no LDAP entry
        if ( !$GroupDN ) {

            # failed login note
            $Self->{LogObject}->Log(
                Priority => 'notice',
                Message =>
                    "CustomerUser: $Param{User} authentication failed, no LDAP group entry found"
                    . "GroupDN='$Self->{GroupDN}', Filter='$Filter2'! (REMOTE_ADDR: $RemoteAddr).",
            );

            # take down session
            $LDAP->unbind;
            $LDAP->disconnect;
            return;
        }
    }

    # bind with user data -> real user auth.
    $Result = $LDAP->bind( dn => $UserDN, password => $Param{Pw} );
    if ( $Result->code ) {

        # failed login note
        $Self->{LogObject}->Log(
            Priority => 'notice',
            Message  => "CustomerUser: $Param{User} ($UserDN) authentication failed: '"
                . $Result->error . "' (REMOTE_ADDR: $RemoteAddr).",
        );

        # take down session
        $LDAP->unbind;
        $LDAP->disconnect;
        return;
    }

    # login note
    $Self->{LogObject}->Log(
        Priority => 'notice',
        Message =>
            "CustomerUser: $Param{User} ($UserDN) authentication ok (REMOTE_ADDR: $RemoteAddr).",
    );

    # take down session
    $LDAP->unbind;
    $LDAP->disconnect;
    return $Param{User};
}

sub _ConvertTo {
    my ( $Self, $Text, $Charset ) = @_;

    return if !defined $Text;

    if ( !$Charset || !$Self->{DestCharset} ) {
        $Self->{EncodeObject}->EncodeInput( \$Text );
        return $Text;
    }

    # convert from input charset ($Charset) to directory charset ($Self->{DestCharset})
    return $Self->{EncodeObject}->Convert(
        Text => $Text,
        From => $Charset,
        To   => $Self->{DestCharset},
    );
}

1;
