set server_url $::env(HW_SERVER_URL)
puts "XSDB: connecting to $server_url"

if {[catch {connect -url $server_url} message]} {
    puts stderr "FAIL: XSDB could not connect: $message"
    exit 3
}

puts "========== AVAILABLE TARGETS =========="
if {[catch {targets} message]} {
    puts stderr "FAIL: Could not enumerate targets: $message"
    disconnect
    exit 4
}
puts "======================================="

if {[catch {targets -set -nocase -filter {name =~ "*PMC*"}} message]} {
    puts stderr "FAIL: No selectable PMC target was found: $message"
    puts stderr "Check board power, cable connection, USB permissions/drivers, and competing Vitis processes."
    disconnect
    exit 5
}

puts "PASS: PMC target is available and selectable."
disconnect
exit 0
