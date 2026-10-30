package VileSkred;
use strict;
use warnings;
use IO::Socket::INET;

# VileSkred: Embedded Perl integration for the vile text editor and Skred audio engine.
# Provides native Perl buffer inspection and UDP datagram dispatch to Skred.

our $PORT = $ENV{SKRED_PORT} || 60440;
our $HOST = $ENV{SKRED_HOST} || '127.0.0.1';

sub send_udp {
    my ($msg) = @_;
    return unless defined $msg && length($msg);
    
    my $sock = IO::Socket::INET->new(
        PeerAddr => $HOST,
        PeerPort => $PORT,
        Proto    => 'udp',
        Timeout  => 1
    );
    if ($sock) {
        $msg =~ s/\r//g;
        $sock->send($msg);
    } else {
        warn "VileSkred: could not send UDP to $HOST:$PORT: $!\n";
    }
}

# Evaluate the line where the cursor currently rests
sub eval_current_line {
    if (defined &Vile::current_line) {
        my $line = Vile::current_line();
        send_udp($line);
        Vile::status("Skred [UDP $PORT]: line sent");
    }
}

# Evaluate the current ## block in the buffer
sub eval_current_block {
    if (defined &Vile::current_buffer && defined &Vile::get_cursor) {
        my $buf = Vile::current_buffer();
        my ($cur_line, $cur_col) = Vile::get_cursor();
        my $total_lines = $buf->lines();
        
        # Search backwards for ##
        my $start = 1;
        for (my $i = $cur_line; $i >= 1; $i--) {
            my $line = $buf->line($i);
            if ($line =~ /^##/) {
                $start = $i + 1;
                last;
            }
        }
        
        # Search forwards for next ##
        my $end = $total_lines;
        for (my $i = $start; $i <= $total_lines; $i++) {
            my $line = $buf->line($i);
            if ($line =~ /^##/) {
                $end = $i - 1;
                last;
            }
        }
        
        if ($start <= $end) {
            my @block_lines;
            for (my $i = $start; $i <= $end; $i++) {
                push @block_lines, $buf->line($i);
            }
            my $payload = join("\n", @block_lines);
            send_udp($payload);
            Vile::status("Skred [UDP $PORT]: block ($start-$end) sent");
        }
    }
}

# Panic stop all voices (*l0)
sub panic {
    send_udp("*l0");
    if (defined &Vile::status) {
        Vile::status("Skred: PANIC (*l0)");
    }
}

# Register commands with vile if embedded Perl is active
if (defined &Vile::register) {
    Vile::register("skred-line", \&eval_current_line, "Send current line to Skred UDP daemon");
    Vile::register("skred-block", \&eval_current_block, "Send current ## block to Skred UDP daemon");
    Vile::register("skred-panic", \&panic, "Silence all Skred voices");
}

1;
