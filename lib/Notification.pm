package Notification;

use Exporter qw(import);
our @ISA = qw(Exporter);
our @EXPORT = qw(email); #functions exported by default
our @EXPORT_OK = qw(); #functions for explicit export

use strict; use warnings; use diagnostics; use feature qw(say);
use Carp;

use MIME::Lite::TT::HTML;

# ==============================================================================
#
#   CAPITAN:        Andres Breton, dev@andresbreton.com
#   FILE:           Notification.pm
#   LICENSE:
#   USAGE:          Send email with attachments
#   DEPENDENCIES:   - MIME::Lite::TT::HTML
#
# ==============================================================================

=head1 NAME

Notification - package

=head1 SYNOPSIS

Creation:
    use Notification;

=head1 DESCRIPTION


=head1 EXPORTS

=head2 Default Behaviors

Exports email subroutine by default

use Notification;

=head2 Optional Behaviors

Notification::;

=head1 FUNCTIONS

=cut

=head2 email

    Arg [1]     : Hash reference with email parameters

    Example     : email(\%params)

    Description : Sends email with attachments

    Returntype  : NULL

    Status      : Development

=cut
sub email {
    my ($params) = @_;

    my $options = {
        'INCLUDE_PATH' => 'lib/templates',
    };

    my $msg = MIME::Lite::TT::HTML->new(
        From        => $params->{'from'},
        To          => $params->{'to'},
        Subject     => $params->{'subject'},
        TimeZone    => 'UTC',
        Template    => {
                            html => 'mail.html',
                            text => 'mail.txt',
                        },
        Charset     => 'utf8',
        TmplOptions => $options,    # reference
        TmplParams  => $params,     # reference
    );

    # Set content type properly
    $msg->attr("content-type"  => "multipart/mixed");

    # Attach PDF to the message
    $msg->attach(   Type        =>  'application/' . $params->{'type'},
                    Path        =>  $params->{'path'},
                    Filename    =>  $params->{'fileName'},
                    Disposition =>  'attachment'
    );

    $msg->send;
    say "Email sent successfully";

    return;
}

1;
