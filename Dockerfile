FROM nousresearch/hermes-agent:latest

USER root
RUN npm install -g @larksuite/cli

USER hermes
