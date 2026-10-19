# Script and stylesheet tags for a Vite entry point (design.md, Decision 5).
# With a dev server configured (development), tags point at it; otherwise
# they come from the build manifest in public/vite.
module ViteHelper
  ENTRYPOINTS = "app/frontend/entrypoints"

  def vite_tags(entry = "application.ts", dev_server: Rails.configuration.x.vite.dev_server, manifest: ViteHelper.manifest)
    source = "#{ENTRYPOINTS}/#{entry}"
    return safe_join([ vite_module_tag("#{dev_server}/vite/@vite/client"), vite_module_tag("#{dev_server}/vite/#{source}") ], "\n") if dev_server

    chunk = manifest.fetch(source)
    imports = vite_imported_chunks(chunk, manifest)
    stylesheets = [ chunk, *imports ].flat_map { |c| c.fetch("css", []) }.uniq

    safe_join([
      *stylesheets.map { |file| tag.link(rel: "stylesheet", href: "/vite/#{file}") },
      vite_module_tag("/vite/#{chunk.fetch("file")}"),
      *imports.map { |c| tag.link(rel: "modulepreload", href: "/vite/#{c.fetch("file")}") }
    ], "\n")
  end

  # The parsed manifest; read once in production, on every call elsewhere so
  # rebuilds are picked up.
  def self.manifest
    return @manifest ||= load_manifest if Rails.configuration.x.vite.cache_manifest

    load_manifest
  end

  def self.load_manifest
    JSON.parse(File.read(Rails.configuration.x.vite.manifest_path))
  end

  private
    def vite_module_tag(src)
      tag.script(src: src, type: "module")
    end

    # Every chunk imported, directly or indirectly, by a chunk.
    def vite_imported_chunks(chunk, manifest, seen = {})
      chunk.fetch("imports", []).each do |key|
        next if seen.key?(key)

        seen[key] = manifest.fetch(key)
        vite_imported_chunks(seen[key], manifest, seen)
      end
      seen.values
    end
end
