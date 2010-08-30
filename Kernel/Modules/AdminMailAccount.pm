# --
# Kernel/Modules/AdminMailAccount.pm - to add/update/delete MailAccount acounts
# Copyright (C) 2001-2010 OTRS AG, http://otrs.org/
# --
# $Id: AdminMailAccount.pm,v 1.17 2010-08-30 21:49:15 cg Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminMailAccount;

use strict;
use warnings;

use Kernel::System::Queue;
use Kernel::System::MailAccount;
use Kernel::System::Valid;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.17 $) [1];

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # check all needed objects
    for (qw(ParamObject DBObject LayoutObject ConfigObject LogObject)) {
        if ( !$Self->{$_} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $_!" );
        }
    }
    $Self->{QueueObject} = Kernel::System::Queue->new(%Param);
    $Self->{MailAccount} = Kernel::System::MailAccount->new(%Param);
    $Self->{ValidObject} = Kernel::System::Valid->new(%Param);

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my %GetParam = ();
    my @Params
        = (qw(ID Login Password Host Type TypeAdd Comment ValidID QueueID Trusted DispatchingBy));
    for (@Params) {
        $GetParam{$_} = $Self->{ParamObject}->GetParam( Param => $_ );
    }

    # ------------------------------------------------------------ #
    # Run
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Run' ) {
        my %Data = $Self->{MailAccount}->MailAccountGet(%GetParam);
        if ( !%Data ) {
            return $Self->{LayoutObject}->ErrorScreen();
        }

        my $Ok = $Self->{MailAccount}->MailAccountFetch(
            %Data,
            Limit  => 15,
            UserID => $Self->{UserID},
        );
        if ( !$Ok ) {
            return $Self->{LayoutObject}->ErrorScreen();
        }
        return $Self->{LayoutObject}->Redirect( OP => 'Action=$Env{"Action"};Ok=1' );
    }

    # ------------------------------------------------------------ #
    # delete
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Delete' ) {
        my $Delete = $Self->{MailAccount}->MailAccountDelete(%GetParam);
        if ( !$Delete ) {
            return $Self->{LayoutObject}->ErrorScreen();
        }
        return $Self->{LayoutObject}->Redirect( OP => 'Action=$Env{"Action"}' );
    }

    # ------------------------------------------------------------ #
    # add new mail account
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'AddNew' ) {

        my ( $Self, %Param ) = @_;

        # get valid list
        my %ValidList        = $Self->{ValidObject}->ValidList();
        my %ValidListReverse = reverse %ValidList;

        # build ValidID string
        $Param{ValidOption} = $Self->{LayoutObject}->BuildSelection(
            Data       => \%ValidList,
            Name       => 'ValidID',
            SelectedID => $Param{ValidID} || $ValidListReverse{valid},
        );

        $Param{TypeOptionAdd} = $Self->{LayoutObject}->BuildSelection(
            Data       => { $Self->{MailAccount}->MailAccountBackendList() },
            Name       => 'TypeAdd',
            SelectedID => $Param{Type} || $Param{TypeAdd} || '',
        );

        $Param{TrustedOption} = $Self->{LayoutObject}->BuildSelection(
            Data       => $Self->{ConfigObject}->Get('YesNoOptions'),
            Name       => 'Trusted',
            SelectedID => $Param{Trusted},
        );

        $Param{DispatchingOption} = $Self->{LayoutObject}->BuildSelection(
            Data => {
                From  => 'Dispatching by email To: field.',
                Queue => 'Dispatching by selected Queue.',
            },
            Name       => 'DispatchingBy',
            SelectedID => $Param{DispatchingBy},
        );

        $Param{QueueOption} = $Self->{LayoutObject}->AgentQueueListOption(
            Data => {
                '' => '-',
                $Self->{QueueObject}->QueueList( Valid => 1 ),
            },
            Name           => 'QueueID',
            SelectedID     => $Param{QueueID},
            OnChangeSubmit => 0,
        );
        $Self->{LayoutObject}->Block(
            Name => 'Overview',
            Data => { %Param, },
        );
        $Self->{LayoutObject}->Block(
            Name => 'ActionList',
        );
        $Self->{LayoutObject}->Block(
            Name => 'ActionOverview',
        );
        $Self->{LayoutObject}->Block(
            Name => 'OverviewAdd',
            Data => { %Param, },
        );
        my $Output = $Self->{LayoutObject}->Header();
        $Output .= $Self->{LayoutObject}->NavigationBar();
        $Output .= $Self->{LayoutObject}->Output(
            TemplateFile => 'AdminMailAccount',
            Data         => \%Param,
        );
        $Output .= $Self->{LayoutObject}->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # add action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'AddAction' ) {

        # challenge token check for write action
        $Self->{LayoutObject}->ChallengeTokenCheck();

        my $ID = $Self->{MailAccount}->MailAccountAdd(
            %GetParam,
            Type          => $GetParam{'TypeAdd'},
            QueueID       => $GetParam{'QueueID'},
            DispatchingBy => $GetParam{'DispatchingBy'},
            Trusted       => $GetParam{'Trusted'},
            ValidID       => $GetParam{'ValidID'},
            UserID        => $Self->{UserID},
        );
        if ( !$ID ) {
            return $Self->{LayoutObject}->ErrorScreen();
        }
        return $Self->{LayoutObject}->Redirect( OP => 'Action=$Env{"Action"}' );
    }

    # ------------------------------------------------------------ #
    # update
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Update' ) {
        my %Data = $Self->{MailAccount}->MailAccountGet(%GetParam);
        if ( !%Data ) {
            return $Self->{LayoutObject}->ErrorScreen();
        }
        return $Self->_MaskUpdate(%Data);
    }

    # ------------------------------------------------------------ #
    # update action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'UpdateAction' ) {

        # challenge token check for write action
        $Self->{LayoutObject}->ChallengeTokenCheck();

        my $Update = $Self->{MailAccount}->MailAccountUpdate(
            %GetParam,
            UserID => $Self->{UserID},
        );
        if ( !$Update ) {
            return $Self->{LayoutObject}->ErrorScreen();
        }
        return $Self->{LayoutObject}->Redirect( OP => 'Action=$Env{"Action"}' );
    }

    # ------------------------------------------------------------ #
    # overview
    # ------------------------------------------------------------ #
    else {
        my $Ok      = $Self->{ParamObject}->GetParam( Param => 'Ok' );
        my %Backend = $Self->{MailAccount}->MailAccountBackendList();
        my %List    = $Self->{MailAccount}->MailAccountList( Valid => 0 );
        $Param{TypeOptionAdd} = $Self->{LayoutObject}->BuildSelection(
            Data       => { $Self->{MailAccount}->MailAccountBackendList() },
            Name       => 'TypeAdd',
            SelectedID => $Param{TypeAdd} || 'POP3',
        );

        $Self->{LayoutObject}->Block(
            Name => 'Overview',
            Data => { %Param, },
        );
        $Self->{LayoutObject}->Block(
            Name => 'ActionList',
        );
        $Self->{LayoutObject}->Block(
            Name => 'ActionAdd',
        );
        $Self->{LayoutObject}->Block(
            Name => 'OverviewResult',
            Data => { %Param, },
        );
        if (%List) {
            for my $Key ( sort { $List{$a} cmp $List{$b} } keys %List ) {
                my %Data = $Self->{MailAccount}->MailAccountGet( ID => $Key );
                if ( !$Backend{ $Data{Type} } ) {
                    $Data{Type} .= '(not installed!)';
                }

                my @List = $Self->{ValidObject}->ValidIDsGet();

                for (@List) {
                    if ( $Data{ValidID} eq $_ ) {
                        $Data{Invalid} = '';
                        last;
                    }
                    else {
                        $Data{Invalid} = 'Invalid';
                    }
                }

                $Data{ShownValid} = $Self->{ValidObject}->ValidLookup(
                    ValidID => $Data{ValidID},
                );

                $Self->{LayoutObject}->Block(
                    Name => 'OverviewResultRow',
                    Data => \%Data,
                );
            }
        }
        else {
            $Self->{LayoutObject}->Block(
                Name => 'NoDataFoundMsg',
                Data => {},
            );
        }

        my $Output = $Self->{LayoutObject}->Header();
        $Output .= $Self->{LayoutObject}->NavigationBar();
        if ($Ok) {
            $Output .= $Self->{LayoutObject}->Notify( Info => 'Finished' );
        }
        $Output .= $Self->{LayoutObject}->Output(
            TemplateFile => 'AdminMailAccount',
            Data         => \%Param,
        );
        $Output .= $Self->{LayoutObject}->Footer();
        return $Output;
    }
}

sub _MaskUpdate {
    my ( $Self, %Param ) = @_;

    # get valid list
    my %ValidList        = $Self->{ValidObject}->ValidList();
    my %ValidListReverse = reverse %ValidList;

    # build ValidID string
    $Param{ValidOption} = $Self->{LayoutObject}->BuildSelection(
        Data       => \%ValidList,
        Name       => 'ValidID',
        SelectedID => $Param{ValidID} || $ValidListReverse{valid},
    );

    $Param{TypeOptionAdd} = $Self->{LayoutObject}->BuildSelection(
        Data       => { $Self->{MailAccount}->MailAccountBackendList() },
        Name       => 'TypeAdd',
        SelectedID => $Param{Type} || $Param{TypeAdd} || '',
    );

    $Param{TypeOption} = $Self->{LayoutObject}->BuildSelection(
        Data       => { $Self->{MailAccount}->MailAccountBackendList() },
        Name       => 'Type',
        SelectedID => $Param{Type} || $Param{TypeAdd} || '',
    );

    $Param{TrustedOption} = $Self->{LayoutObject}->BuildSelection(
        Data       => $Self->{ConfigObject}->Get('YesNoOptions'),
        Name       => 'Trusted',
        SelectedID => $Param{Trusted},
    );

    $Param{DispatchingOption} = $Self->{LayoutObject}->BuildSelection(
        Data => {
            From  => 'Dispatching by email To: field.',
            Queue => 'Dispatching by selected Queue.',
        },
        Name       => 'DispatchingBy',
        SelectedID => $Param{DispatchingBy},
    );

    $Param{QueueOption} = $Self->{LayoutObject}->AgentQueueListOption(
        Data => {
            '' => '-',
            $Self->{QueueObject}->QueueList( Valid => 1 ),
        },
        Name           => 'QueueID',
        SelectedID     => $Param{QueueID},
        OnChangeSubmit => 0,
    );
    $Self->{LayoutObject}->Block(
        Name => 'Overview',
        Data => { %Param, },
    );
    $Self->{LayoutObject}->Block(
        Name => 'ActionList',
    );
    $Self->{LayoutObject}->Block(
        Name => 'ActionOverview',
    );
    $Self->{LayoutObject}->Block(
        Name => 'OverviewUpdate',
        Data => { %Param, },
    );
    my $Output = $Self->{LayoutObject}->Header();
    $Output .= $Self->{LayoutObject}->NavigationBar();
    $Output .= $Self->{LayoutObject}->Output(
        TemplateFile => 'AdminMailAccount',
        Data         => \%Param,
    );
    $Output .= $Self->{LayoutObject}->Footer();
    return $Output;
}
1;
