FROM nousresearch/hermes-agent:latest

USER root
RUN LATEST=$(npm view @larksuite/cli version 2>/dev/null) && \
    CURRENT=$(lark --version 2>/dev/null | grep -oP '[\d.]+$' || true) && \
    if [ "$CURRENT" != "$LATEST" ]; then \
      echo "Upgrading @larksuite/cli ${CURRENT:-not installed} -> ${LATEST}" && \
      npm install -g @larksuite/cli@latest; \
    else \
      echo "@larksuite/cli already up-to-date (${LATEST})"; \
    fi

USER hermes
