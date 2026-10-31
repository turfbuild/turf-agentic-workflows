# A compact view of the plan document `show` returns: one line per resource change and per
# drifted resource, with the attributes that differ, then the output changes. Run it on the
# saved plan when the document is too large to read whole:
#   jq -c -f .github/workflows/shared/plan-summary.jq <file>
# A value marked sensitive anywhere inside it prints as "(sensitive)"; one known only after
# the apply prints as "(known after apply)".

def obj: if type == "object" then . else {} end;
def marked: [.. | select(. == true)] | length > 0;

def diff:
  (.before | obj) as $b | (.after | obj) as $a | (.after_unknown | obj) as $u
  | (.before_sensitive | obj) as $bs | (.after_sensitive | obj) as $as
  | [($b + $a + $u | keys_unsorted[]) as $k
     | select($u[$k] == true or $a[$k] != $b[$k])
     | {($k): (if ($bs[$k] | marked) or ($as[$k] | marked) then "(sensitive)"
               elif $u[$k] == true then [$b[$k], "(known after apply)"]
               else [$b[$k], $a[$k]] end)}]
  | add // {};

(.resource_changes[]? | select(.change.actions != ["no-op"])
  | {change: .address, actions: .change.actions}
    + (if .change.actions == ["create"] or .change.actions == ["delete"] then {}
       else {diff: (.change | diff)} end)
    + (if .change.replace_paths then {replace: .change.replace_paths} else {} end)),
(.resource_drift[]? | {drift: .address, diff: (.change | diff)}),
{outputs: (.output_changes // {} | map_values(.actions) | with_entries(select(.value != ["no-op"])))}
