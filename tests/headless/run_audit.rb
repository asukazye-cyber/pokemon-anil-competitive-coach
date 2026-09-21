# Runs the post-merge audit regression suite (T7) on its own:
#   python3 tools/rubyrun.py . package/dist/ruby+stdlib.wasm \
#     file tests/headless/boot.rb tests/headless/run_audit.rb
#
# run_engine2.rb (64 checks + the shipped-rxdata smoke) stays the acceptance
# gate for the shipped artifact; T7 pins the audit fixes separately so that
# gate keeps the same shape it had at merge time.
begin
  load "/work/tests/headless/t7_audit.rb"
rescue SystemExit
  # t7 calls exit; capture
end
