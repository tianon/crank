(import [crank.utils [group-map one]])


(defmacro in-workdir [&rest params]
  "Run the forms in a temporary directory and remove it."
  `(do (import [crank.utils [cdtmp]])
       (with [[(cdtmp)]] ~@params)))


(defmacro/g! build [&rest params]
  (let [[mapping (group-map keyword? params)]]
    `(do (import dput datetime requests urllib.parse
                 [crank.utils [git-clone git-clone-debian
                               prepare-changelog prepare-source
                               sign-source build-tarball]]
                 [glob [glob]]
                 [os [environ chdir]])

         (setv (get environ "DEBEMAIL")
              ~(one 'nil (:maintainer-email mapping)))

         (setv (get environ "DEBFULLNAME")
              ~(one 'nil (:maintainer-name mapping)))

         (setv remote ~(one 'nil (:upload-location mapping)))

         (for [dist [~@(:suites mapping)]]
           (print "Building for" dist)
           (in-workdir
             (setv source ~(one 'nil (:source mapping)))

             (print "Cloning into" source "(just a sec)")
             (git-clone ~(one 'nil (:upstream mapping)) source)
             (chdir source)

             (setv version (.strip ~(one 'nil (:version mapping))))
             (print "Building version" version)

             (setv tarball (build-tarball source version))
             (print "Tarball built as" tarball)

             (git-clone-debian ~(one 'nil (:debian mapping)))
             (print "Debian overlay pulled down")

             (setv dversion (prepare-changelog version dist))
             (print "Changelog prepared.")
             (print "Version:" dversion)

             (setv url (apply remote.format [] {
               "version" dversion
               "upstream-version" version
               "source" source
             }))

             (setv response (requests.head url))
             (if (!= response.status-code 404)
               (do (print dversion "already present in the remote")
                   (continue))
               (print "Remote doesn't have" dversion))

             (prepare-source)
             (print "Source distribution prepared.")
             (let [[(, changes) (glob (.format "../{}*{}*source*changes" source version))]
                   [key ~(one 'nil (:key mapping))]
                   [target ~(one 'nil (:target mapping))]]
               (print "Signing" changes "with" key)
               (sign-source changes key)
               (print "Uploading" changes "to" target)
               (dput.upload changes target)))))))
