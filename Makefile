@PHONY: all build run clean export-client-html docker-client-build-run docker-client-run docker-client-rm docker-client-update gcp-trigger-build gcp-init-dns

GODOT_BINARY = godot
export-client-html:
		$(GODOT_BINARY) --headless --path $(shell pwd) --export-release "Web" $(shell pwd)/builds/client-html/index.html


# =========================== ITCH SECTION ===========================
itch-build-zip: export-client-html
		rm -f builds/client-html.zip
		cd builds && zip -r client-html.zip client-html

itch-login:
		butler login

itch-upload: itch-build-zip
		butler push builds/client-html.zip muchachoo/tomatoe-mmo:client-html

