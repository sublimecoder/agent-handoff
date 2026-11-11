#!/bin/sh
# Secrets guard tests, run against hooks/secrets-guard.sh. Plain sh; each test is a function run in a subshell.
HERE=$(cd "$(dirname "$0")" && pwd)
HOOKS="$HERE/../hooks"
FX="$HERE/fixtures"

fail() { echo "    $*" >&2; exit 1; }

setup() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/agent-handoff-guard.XXXXXX") || exit 1
  trap 'rm -rf "$T"' EXIT
}

# run <script> <stdin-file>; sets rc, and $T/out, $T/err
run() {
  sh "$HOOKS/$1" < "$2" > "$T/out" 2> "$T/err"
  rc=$?
}
want_rc() { [ "$rc" -eq "$1" ] || fail "exit $rc, want $1 (stderr: $(cat "$T/err"))"; }

guard_blocks() {
  run secrets-guard.sh "$FX/$1.json"
  want_rc 2
  grep -q 'secrets-guard' "$T/err" || fail "stderr lacks secrets-guard"
}
guard_allows() { run secrets-guard.sh "$FX/$1.json"; want_rc 0; }

test_guard_blocks_env_read() { guard_blocks read_env; }
test_guard_blocks_env_variant() { guard_blocks read_env_production; }
test_guard_allows_env_example() { guard_allows read_env_example; }
test_guard_blocks_bash_cat() { guard_blocks bash_cat_env; guard_blocks codex_bash_cat_env; }
test_guard_blocks_keys() { guard_blocks read_ssh_key; guard_blocks read_pem; guard_blocks read_key; }
test_guard_allows_pub_key() { guard_allows read_pub_key; }
test_guard_allows_normal() { guard_allows read_normal; guard_allows bash_grep_normal; guard_allows write_process_env; }
test_guard_allows_write_content_mentioning_env() { guard_allows write_gitignore; }
test_guard_ignores_cwd_env_dir() { guard_allows read_cwd_env_dir; }
test_guard_blocks_apply_patch_env() { guard_blocks patch_env; }
test_guard_blocks_indented_patch_header() { guard_blocks patch_env_indented; guard_blocks patch_env_tight; }
test_guard_blocks_quoted_names() { for f in q_empty_quotes q_single_quotes q_quoted_tail q_bracket_class q_ansi_c q_backslash q_key_quoted; do guard_blocks "$f"; done; }
test_guard_allows_quoted_plain() { guard_allows q_allows_quoted_plain; }
test_guard_second_pass_keeps_exemptions() { for f in q_ok_process_env_index q_ok_json_env_example q_ok_json_pub q_ok_json_key_ts q_ok_bracket_env_name q_ok_jq_bracket q_ok_read_bracket_path; do guard_allows "$f"; done; }
test_guard_blocks_backslash_newline_and_vtab_header() { guard_blocks q_backslash_newline; guard_blocks patch_env_vtab; }
test_guard_allows_apply_patch_content() { guard_allows patch_content; }
test_guard_blocks_named_env() { guard_blocks read_config_env; }
test_guard_blocks_p12() { guard_blocks read_p12; }
test_guard_blocks_netrc() { guard_blocks read_netrc; }
test_guard_allows_avoid_rsa() { guard_allows read_avoid_rsa; }
test_guard_blocks_id_ecdsa() { guard_blocks read_id_ecdsa; }
test_guard_blocks_pub_traversal() { guard_blocks pub_traversal; }
test_guard_blocks_bash_pub_and_env() { guard_blocks bash_pub_and_env; }
test_guard_blocks_grep_env_path() { guard_blocks grep_env_path; }
test_guard_blocks_glob_env() { guard_blocks glob_env; }
test_guard_blocks_unknown_tool_path() { guard_blocks unknown_tool_path; }
test_guard_allows_unknown_tool_content() { guard_allows unknown_tool_content; }
test_guard_blocks_named_env_suffix() { guard_blocks read_env_suffix; }
test_guard_blocks_key_data_suffixes() { guard_blocks read_key_json; guard_blocks read_key_md; guard_blocks read_p12_ts; }
test_guard_allows_x_env_example() { guard_allows read_x_env_example; }
test_guard_allows_bash_process_env() { guard_allows bash_process_env; }
test_guard_blocks_codex_shell_array() { guard_blocks codex_shell_array; }
test_guard_blocks_paths_array_first() { guard_blocks paths_array_first; }
test_guard_blocks_paths_array_later() { guard_blocks paths_array_later; }
test_guard_blocks_process_env_dir_traversal() { guard_blocks bash_process_env_trav1; guard_blocks bash_process_env_trav2; }
test_guard_blocks_array_with_bracket() { guard_blocks paths_array_bracket; }
test_guard_blocks_multiline_array() { guard_blocks paths_array_multiline; }
test_guard_blocks_nested_object_path() { guard_blocks nested_object_path; }
test_guard_allows_escaped_quote_in_content() { guard_allows write_escaped_quote; }
test_guard_blocks_codex_command_array_bracket() { guard_blocks codex_shell_array_bracket; }
test_guard_blocks_begin_patch_bypass() { guard_blocks bash_begin_patch_bypass; guard_blocks shell_begin_patch_bypass; }
test_guard_allows_shell_apply_patch_content() { guard_allows shell_apply_patch_content; }
test_guard_blocks_shell_apply_patch_env() { guard_blocks shell_apply_patch_env; }
test_guard_allows_prose_fields() { guard_allows agent_prompt_env; guard_allows bash_description_env; }
test_guard_blocks_command_despite_description() { guard_blocks bash_description_cat_env; }
test_guard_reads_top_level_tool_name() { guard_blocks nested_tool_name_patch; guard_blocks nested_tool_name_grep; }
test_guard_blocks_apply_patch_arg_bypass() { guard_blocks shell_patch_arg_bypass; guard_blocks shell_patch_eval_bypass; guard_blocks shell_patch_echo_bypass; guard_blocks shell_patch_number_bypass; }
test_guard_prose_skip_is_per_tool() { guard_blocks mcp_query_env; guard_blocks unknown_description_env; guard_blocks bash_prompt_env; }
test_guard_key_ext_must_end_token() {
  guard_allows read_key_ts
  guard_blocks bash_cat_tls_key; guard_blocks read_a_server_pem; guard_blocks bash_redis_session_key
}
test_guard_r14_dotfile_keys_block() {
  guard_blocks r14_cat_dot_tls_key; guard_blocks r14_cat_dot_server_pem
  guard_blocks r14_openssl_dot_pem; guard_blocks r14_read_dot_deploy_key
  guard_blocks r14_jq_file_dot_key; guard_blocks r14_jq_filter_subst
  guard_blocks r14_jq_brace_expansion; guard_blocks r14_jq_glob
}
test_guard_r14_key_backups_block() {
  guard_blocks r14_cat_key_bak; guard_blocks r14_xxd_key_bak; guard_blocks r14_read_key_bak
  guard_blocks r14_cat_key_orig; guard_blocks r14_cat_key_1; guard_blocks r14_cp_pem_bak
  guard_allows read_key_ts
}
test_guard_r14_call_words_block() {
  guard_blocks r14_cat_call_word; guard_blocks r14_basename_pem
  guard_blocks r14_python_open_key; guard_blocks r14_node_read_key; guard_blocks r14_node_extra_arg
}
# R15: no relaxation for jq filters or interpreter code; key-like names block.
test_guard_r15_key_like_names_in_commands_block() {
  guard_blocks bash_jq_key; guard_blocks bash_jq_nested_key; guard_blocks r14_jq_quoted_nested_key
  guard_blocks r14_jq_items_key; guard_blocks bash_node_obj_key; guard_blocks r14_codex_node_obj_key
}
test_guard_r15_scan_bypasses_block() {
  guard_blocks r15_jq_redirect_dot_key; guard_blocks r15_jq_rf_cluster
  guard_blocks r15_jq_rawfile_eq; guard_blocks r15_ruby_percent_q
}
test_guard_malformed_input_allows() { run secrets-guard.sh "$FX/malformed.txt"; want_rc 0; }

pass=0; failed=0
names=$(sed -n 's/^\(test_[a-z0-9_]*\)().*/\1/p' "$0")
for name in $names; do
  if ( setup; "$name" ) < /dev/null; then
    pass=$((pass + 1)); echo "PASS ${name#test_}"
  else
    failed=$((failed + 1)); echo "FAIL ${name#test_}"
  fi
done
echo "test_guard: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
