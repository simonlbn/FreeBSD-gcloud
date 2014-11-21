Script to generate FreeBSD Google Cloud images
==============================================

Here's the basic beginnings of my script to create Google Cloud images for
FreeBSD. Needs lots of work.

* Requires these pkgs (ports):
    bar (textproc/bar)
    gtar (archivers/gtar)
    google-cloud-sdk (net/google-cloud-sdk)

* best run on the same version of the OS that images are being created for,
  since newfs is used from the host

* You should login to GCloud before running
