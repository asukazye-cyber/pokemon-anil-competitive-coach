# Runs the full Engine 2.0 suite.
#
# t5 runs FIRST and deliberately does NOT use load_engine2: it evaluates the
# engine2 sources EXACTLY AS SHIPPED inside game/Scripts.rxdata (parsed from
# the built file). That both validates the deliverable artifact and brings
# CoachEngine2 into scope for the remaining suites; load_engine2 is then a
# no-op fallback (only needed if the rxdata smoke failed).
tests = %w[
  t5_rxdata_smoke
  t1_twin_smoke
  t2_mandatory
  t3_from_live
  t4_integration
  t6_search2
]
tests.each do |t|
  puts "===== #{t} ====="
  load_engine2 unless defined?(CoachEngine2::Search) || t == "t5_rxdata_smoke"
  begin
    load "/work/tests/headless/#{t}.rb"
  rescue SystemExit
    # test files call exit; capture
  end
end
