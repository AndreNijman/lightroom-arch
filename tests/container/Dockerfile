FROM archlinux:latest

RUN pacman -Syu --noconfirm --needed base-devel git && \
  pacman -Scc --noconfirm

WORKDIR /work/lightroom-arch

CMD ["tests/smoke.sh", "--dry-run"]
