require Rails.root.join("lib/plywo/rails/evidence").to_s
require Rails.root.join("lib/plywo/rails/source_locator").to_s
require Rails.root.join("lib/plywo/rails/durable_evidence_buffer").to_s
require Rails.root.join("lib/plywo/rails/net_http_instrumentation").to_s
require Rails.root.join("lib/plywo/rails/runtime_evidence_bridge").to_s

Plywo::Rails::RuntimeEvidenceBridge.install!
