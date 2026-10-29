# backblaze-bucket-owners (LIB-0045 §5): only the workloads in
# $params.workloads own Backblaze buckets. A B2 key in a hand-written leaf
# fails too, since no grant (LIB-0045 §6) covers it. A key a workload declares
# passes: resolve-workloads.sh holds it to its own buckets and granted ones.
($params | objects | keys - ["workloads"]) as $extra
| if $extra != [] then error("\($extra | join(", ")) isn't a param; the one param is workloads") else . end
| ($params.workloads
   | if type == "array" and length > 0 and all(.[]; type == "string" and test("^[^/]+/[a-z0-9-]+$")) then .
     else error("needs workloads: a list of the workload IDs, <parent>/<workload>, that may own Backblaze buckets") end) as $owners
| .[]
| ((.modules | index("backblaze/bucket") != null) or (.resources | index("b2_bucket") != null)) as $bucket
| ((.modules | index("backblaze/api-key") != null) or (.resources | index("b2_application_key") != null)) as $key
| if $bucket and ((.unit.type == "workload" and (.unit.id | IN($owners[]))) | not) then
    {path, file, line,
     message: "\(if .unit.type == "spoke" then "hand-written leaf \(.unit.id) holds a Backblaze bucket" else "\(.unit.type) \(.unit.id) holds Backblaze bucket \(.instance)" end); only \($owners | join(", ")) may own one. Another workload reaches a bucket through a key, once its owner grants it (policies.yaml, LIB-0045 §§5-6)"}
  elif $key and .unit.type == "spoke" then
    {path, file, line,
     message: "hand-written leaf \(.unit.id) holds a B2 key, which no grant covers; declare it as backblaze.apiKey in a workload (LIB-0045 §5)"}
  else empty end
