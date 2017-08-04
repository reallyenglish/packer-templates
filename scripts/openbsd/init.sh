#!/bin/ksh

set -e
set -x

sudo tee /etc/pkg.conf <<EOF
installpath = ftp.openbsd.org
EOF

sudo pkg_add ansible rsync--
sudo ln -sf /usr/local/bin/python2.7 /usr/local/bin/python
sudo ln -sf /usr/local/bin/python2.7-2to3 /usr/local/bin/2to3
sudo ln -sf /usr/local/bin/python2.7-config /usr/local/bin/python-config
sudo ln -sf /usr/local/bin/pydoc2.7  /usr/local/bin/pydoc

sudo pkg_add curl

sudo tee /etc/rc.conf.local <<EOF
sndiod_flags=NO
sendmail_flags=NO
EOF

if [ `uname -r` == "6.0" || `uname -r` == "6.1" ]; then
    sudo patch -p1 -d /usr/local/lib/python2.7/site-packages/ansible/modules/extras <<EOF
From 39d0088af8b4d03df38b464d9cb87864cd1c2885 Mon Sep 17 00:00:00 2001
From: Patrik Lundin <patrik@sigterm.se>
Date: Wed, 29 Jun 2016 23:27:31 +0200
Subject: [PATCH 1/9] openbsd_pkg: support "pkgname%branch" syntax.

* Such package names requires at least OpenBSD 6.0.

* Rework get_package_state() to use 'pkg_info -Iq inst:' instead of 'pkg_info -e'
  because it understands the branch syntax. It also means we can get rid of
  some additional special handling.

  This was suggested by Marc Espie:
  http://marc.info/?l=openbsd-tech&m=146659756711614&w=2

* Drop get_current_name() because the use of 'pkg_info -Iq inst:' in
  get_package_state() means we already have that information available without
  needing to do custom parsing. This was also necessary because a name such as
  "postfix%stable" does not in itself contain the version information necessary
  for the custom parsing. pkg_info -Iq translates such a name to the actual
  package name seamlessly.

* Add support for finding more than one package for the supplied package name
  which may happen if we only supply a stem.
---
 packaging/os/openbsd_pkg.py | 95 +++++++++++++++++++++++----------------------
 1 file changed, 48 insertions(+), 47 deletions(-)

diff --git a/packaging/os/openbsd_pkg.py b/packaging/os/openbsd_pkg.py
index 9700e831892..354b7463093 100644
--- a/packaging/os/openbsd_pkg.py
+++ b/packaging/os/openbsd_pkg.py
@@ -19,10 +19,13 @@
 # along with Ansible.  If not, see <http://www.gnu.org/licenses/>.
 
 import os
+import platform
 import re
 import shlex
 import sqlite3
 
+from distutils.version import StrictVersion
+
 DOCUMENTATION = '''
 ---
 module: openbsd_pkg
@@ -82,6 +85,9 @@
 # Specify the default flavour to avoid ambiguity errors
 - openbsd_pkg: name=vim-- state=present
 
+# Specify a package branch (requires at least OpenBSD 6.0)
+- openbsd_pkg: name=python%3.5 state=present
+
 # Update all packages on the system
 - openbsd_pkg: name=* state=latest
 '''
@@ -94,47 +100,22 @@ def execute_command(cmd, module):
     cmd_args = shlex.split(cmd)
     return module.run_command(cmd_args)
 
-# Function used for getting the name of a currently installed package.
-def get_current_name(name, pkg_spec, module):
-    info_cmd = 'pkg_info'
-    (rc, stdout, stderr) = execute_command("%s" % (info_cmd), module)
-    if rc != 0:
-        return (rc, stdout, stderr)
-
-    if pkg_spec['version']:
-        pattern = "^%s" % name
-    elif pkg_spec['flavor']:
-        pattern = "^%s-.*-%s\s" % (pkg_spec['stem'], pkg_spec['flavor'])
-    else:
-        pattern = "^%s-" % pkg_spec['stem']
-
-    module.debug("get_current_name(): pattern = %s" % pattern)
-
-    for line in stdout.splitlines():
-        module.debug("get_current_name: line = %s" % line)
-        match = re.search(pattern, line)
-        if match:
-            current_name = line.split()[0]
-
-    return current_name
-
 # Function used to find out if a package is currently installed.
 def get_package_state(name, pkg_spec, module):
-    info_cmd = 'pkg_info -e'
+    info_cmd = 'pkg_info -Iq'
 
-    if pkg_spec['version']:
-        command = "%s %s" % (info_cmd, name)
-    elif pkg_spec['flavor']:
-        command = "%s %s-*-%s" % (info_cmd, pkg_spec['stem'], pkg_spec['flavor'])
-    else:
-        command = "%s %s-*" % (info_cmd, pkg_spec['stem'])
+    command = "%s inst:%s" % (info_cmd, name)
 
     rc, stdout, stderr = execute_command(command, module)
 
-    if (stderr):
+    if stderr:
         module.fail_json(msg="failed in get_package_state(): " + stderr)
 
-    if rc == 0:
+    if stdout:
+        # If the requested package name is just a stem, like "python", we may
+        # find multiple packages with that name.
+        pkg_spec['installed_names'] = [line.rstrip() for line in stdout.splitlines()]
+        module.debug("get_package_state(): installed_names = %s" % pkg_spec['installed_names'])
         return True
     else:
         return False
@@ -173,8 +154,14 @@ def package_present(name, installed_state, pkg_spec, module):
         # specific version is supplied or not.
         #
         # When a specific version is supplied the return code will be 0 when
-        # a package is found and 1 when it is not, if a version is not
-        # supplied the tool will exit 0 in both cases:
+        # a package is found and 1 when it is not. If a version is not
+        # supplied the tool will exit 0 in both cases.
+        #
+        # It is important to note that "version" relates to the
+        # packages-specs(7) notion of a version. If using the branch syntax
+        # (like "python%3.5") the version number is considered part of the
+        # stem, and the pkg_add behavior behaves the same as if the name did
+        # not contain a version (which it strictly speaking does not).
         if pkg_spec['version'] or build is True:
             # Depend on the return code.
             module.debug("package_present(): depending on return code")
@@ -231,25 +218,21 @@ def package_latest(name, installed_state, pkg_spec, module):
 
     if installed_state is True:
 
-        # Fetch name of currently installed package.
-        pre_upgrade_name = get_current_name(name, pkg_spec, module)
-
-        module.debug("package_latest(): pre_upgrade_name = %s" % pre_upgrade_name)
-
         # Attempt to upgrade the package.
         (rc, stdout, stderr) = execute_command("%s %s" % (upgrade_cmd, name), module)
 
         # Look for output looking something like "nmap-6.01->6.25: ok" to see if
         # something changed (or would have changed). Use \W to delimit the match
         # from progress meter output.
-        match = re.search("\W%s->.+: ok\W" % pre_upgrade_name, stdout)
-        if match:
-            if module.check_mode:
-                module.exit_json(changed=True)
+        changed = False
+        for installed_name in pkg_spec['installed_names']:
+            module.debug("package_latest(): checking for pre-upgrade package name: %s" % installed_name)
+            match = re.search("\W%s->.+: ok\W" % installed_name, stdout)
+            if match:
+                if module.check_mode:
+                    module.exit_json(changed=True)
 
-            changed = True
-        else:
-            changed = False
+                changed = True
 
         # FIXME: This part is problematic. Based on the issues mentioned (and
         # handled) in package_present() it is not safe to blindly trust stderr
@@ -301,7 +284,12 @@ def package_absent(name, installed_state, module):
 
 # Function used to parse the package name based on packages-specs(7).
 # The general name structure is "stem-version[-flavors]".
+#
+# Names containing "%" are a special variation not part of the
+# packages-specs(7) syntax. See pkg_add(1) on OpenBSD 6.0 or later for a
+# description.
 def parse_package_name(name, pkg_spec, module):
+    module.debug("parse_package_name(): parsing name: %s" % name)
     # Do some initial matches so we can base the more advanced regex on that.
     version_match = re.search("-[0-9]", name)
     versionless_match = re.search("--", name)
@@ -350,6 +338,19 @@ def parse_package_name(name, pkg_spec, module):
         else:
             module.fail_json(msg="Unable to parse package name at else: " + name)
 
+    # If the stem contains an "%" then it needs special treatment.
+    branch_match = re.search("%", pkg_spec['stem'])
+    if branch_match:
+
+        branch_release = "6.0"
+
+        if version_match or versionless_match:
+            module.fail_json(msg="Package name using 'branch' syntax also has a version or is version-less: " + name)
+        if StrictVersion(platform.release()) < StrictVersion(branch_release):
+            module.fail_json(msg="Package name using 'branch' syntax requires at least OpenBSD %s: %s" % (branch_release, name))
+
+        pkg_spec['style'] = 'branch'
+
     # Sanity check that there are no trailing dashes in flavor.
     # Try to stop strange stuff early so we can be strict later.
     if pkg_spec['flavor']:

From f4b40926b4f8bb847b950ba832f96b0860021725 Mon Sep 17 00:00:00 2001
From: Patrik Lundin <patrik@sigterm.se>
Date: Wed, 29 Jun 2016 23:57:31 +0200
Subject: [PATCH 2/9] openbsd_pkg: fix build=true corner case.

* Fix bug where we were actually checking for the availability of the
  requested package name and not 'sqlports' even if that was the goal.

* Add check that the sqlports database file exists before using it.

* Sprinkle some debug messages for an easier time following the code when
  developing.
---
 packaging/os/openbsd_pkg.py | 13 +++++++++++--
 1 file changed, 11 insertions(+), 2 deletions(-)

diff --git a/packaging/os/openbsd_pkg.py b/packaging/os/openbsd_pkg.py
index 354b7463093..ff9ef672ca7 100644
--- a/packaging/os/openbsd_pkg.py
+++ b/packaging/os/openbsd_pkg.py
@@ -365,9 +365,14 @@ def get_package_source_path(name, pkg_spec, module):
         return 'databases/sqlports'
     else:
         # try for an exact match first
-        conn = sqlite3.connect('/usr/local/share/sqlports')
+        sqlports_db_file = '/usr/local/share/sqlports'
+        if not os.path.isfile(sqlports_db_file):
+            module.fail_json(msg="sqlports file '%s' is missing" % sqlports_db_file)
+
+        conn = sqlite3.connect(sqlports_db_file)
         first_part_of_query = 'SELECT fullpkgpath, fullpkgname FROM ports WHERE fullpkgname'
         query = first_part_of_query + ' = ?'
+        module.debug("package_package_source_path(): query: %s" % query)
         cursor = conn.execute(query, (name,))
         results = cursor.fetchall()
 
@@ -377,11 +382,14 @@ def get_package_source_path(name, pkg_spec, module):
             query = first_part_of_query + ' LIKE ?'
             if pkg_spec['flavor']:
                 looking_for += pkg_spec['flavor_separator'] + pkg_spec['flavor']
+                module.debug("package_package_source_path(): flavor query: %s" % query)
                 cursor = conn.execute(query, (looking_for,))
             elif pkg_spec['style'] == 'versionless':
                 query += ' AND fullpkgname NOT LIKE ?'
+                module.debug("package_package_source_path(): versionless query: %s" % query)
                 cursor = conn.execute(query, (looking_for, "%s-%%" % looking_for,))
             else:
+                module.debug("package_package_source_path(): query: %s" % query)
                 cursor = conn.execute(query, (looking_for,))
             results = cursor.fetchall()
 
@@ -465,8 +473,9 @@ def main():
         # build sqlports if its not installed yet
         pkg_spec = {}
         parse_package_name('sqlports', pkg_spec, module)
-        installed_state = get_package_state(name, pkg_spec, module)
+        installed_state = get_package_state('sqlports', pkg_spec, module)
         if not installed_state:
+            module.debug("main(): installing sqlports")
             package_present('sqlports', installed_state, pkg_spec, module)
 
     if name == '*':

From 7dcac77df5ea7f7d4ad3ce785a26472e65d8ff07 Mon Sep 17 00:00:00 2001
From: Patrik Lundin <patrik@sigterm.se>
Date: Thu, 30 Jun 2016 00:38:57 +0200
Subject: [PATCH 3/9] openbsd_pkg: no need to call .rstrip.

---
 packaging/os/openbsd_pkg.py | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

diff --git a/packaging/os/openbsd_pkg.py b/packaging/os/openbsd_pkg.py
index ff9ef672ca7..305b7c06454 100644
--- a/packaging/os/openbsd_pkg.py
+++ b/packaging/os/openbsd_pkg.py
@@ -114,7 +114,7 @@ def get_package_state(name, pkg_spec, module):
     if stdout:
         # If the requested package name is just a stem, like "python", we may
         # find multiple packages with that name.
-        pkg_spec['installed_names'] = [line.rstrip() for line in stdout.splitlines()]
+        pkg_spec['installed_names'] = [name for name in stdout.splitlines()]
         module.debug("get_package_state(): installed_names = %s" % pkg_spec['installed_names'])
         return True
     else:

From c118bcab5cad9037d6bf31778668799ba899dea3 Mon Sep 17 00:00:00 2001
From: Patrik Lundin <patrik@sigterm.se>
Date: Thu, 30 Jun 2016 17:30:28 +0200
Subject: [PATCH 4/9] Add a break and extra debug log for clarity.

---
 packaging/os/openbsd_pkg.py | 2 ++
 1 file changed, 2 insertions(+)

diff --git a/packaging/os/openbsd_pkg.py b/packaging/os/openbsd_pkg.py
index 305b7c06454..2e31d16b426 100644
--- a/packaging/os/openbsd_pkg.py
+++ b/packaging/os/openbsd_pkg.py
@@ -229,10 +229,12 @@ def package_latest(name, installed_state, pkg_spec, module):
             module.debug("package_latest(): checking for pre-upgrade package name: %s" % installed_name)
             match = re.search("\W%s->.+: ok\W" % installed_name, stdout)
             if match:
+                module.debug("package_latest(): package name match: %s" % installed_name)
                 if module.check_mode:
                     module.exit_json(changed=True)
 
                 changed = True
+                break
 
         # FIXME: This part is problematic. Based on the issues mentioned (and
         # handled) in package_present() it is not safe to blindly trust stderr

From 2d353dc98cb7fe9f5082902a1a7fc2e89e4ebe69 Mon Sep 17 00:00:00 2001
From: Patrik Lundin <patrik@sigterm.se>
Date: Thu, 30 Jun 2016 17:41:17 +0200
Subject: [PATCH 5/9] Improve debug logging for build code.

---
 packaging/os/openbsd_pkg.py | 8 ++++----
 1 file changed, 4 insertions(+), 4 deletions(-)

diff --git a/packaging/os/openbsd_pkg.py b/packaging/os/openbsd_pkg.py
index 2e31d16b426..eae57a695c7 100644
--- a/packaging/os/openbsd_pkg.py
+++ b/packaging/os/openbsd_pkg.py
@@ -374,7 +374,7 @@ def get_package_source_path(name, pkg_spec, module):
         conn = sqlite3.connect(sqlports_db_file)
         first_part_of_query = 'SELECT fullpkgpath, fullpkgname FROM ports WHERE fullpkgname'
         query = first_part_of_query + ' = ?'
-        module.debug("package_package_source_path(): query: %s" % query)
+        module.debug("package_package_source_path(): exact query: %s" % query)
         cursor = conn.execute(query, (name,))
         results = cursor.fetchall()
 
@@ -384,14 +384,14 @@ def get_package_source_path(name, pkg_spec, module):
             query = first_part_of_query + ' LIKE ?'
             if pkg_spec['flavor']:
                 looking_for += pkg_spec['flavor_separator'] + pkg_spec['flavor']
-                module.debug("package_package_source_path(): flavor query: %s" % query)
+                module.debug("package_package_source_path(): fuzzy flavor query: %s" % query)
                 cursor = conn.execute(query, (looking_for,))
             elif pkg_spec['style'] == 'versionless':
                 query += ' AND fullpkgname NOT LIKE ?'
-                module.debug("package_package_source_path(): versionless query: %s" % query)
+                module.debug("package_package_source_path(): fuzzy versionless query: %s" % query)
                 cursor = conn.execute(query, (looking_for, "%s-%%" % looking_for,))
             else:
-                module.debug("package_package_source_path(): query: %s" % query)
+                module.debug("package_package_source_path(): fuzzy query: %s" % query)
                 cursor = conn.execute(query, (looking_for,))
             results = cursor.fetchall()
 

From dd14d142240b821691c2865f2ab6a078ccb6cd9f Mon Sep 17 00:00:00 2001
From: Patrik Lundin <patrik@sigterm.se>
Date: Thu, 30 Jun 2016 18:13:40 +0200
Subject: [PATCH 6/9] No support for build=true with 'branch' syntax.

---
 packaging/os/openbsd_pkg.py | 5 +++++
 1 file changed, 5 insertions(+)

diff --git a/packaging/os/openbsd_pkg.py b/packaging/os/openbsd_pkg.py
index eae57a695c7..de37a769b05 100644
--- a/packaging/os/openbsd_pkg.py
+++ b/packaging/os/openbsd_pkg.py
@@ -491,6 +491,11 @@ def main():
         pkg_spec = {}
         parse_package_name(name, pkg_spec, module)
 
+        # Not sure how the branch syntax is supposed to play together
+        # with build mode. Disable it for now.
+        if pkg_spec['style'] == 'branch' and module.params['build'] is True:
+            module.fail_json(msg="the combination of 'branch' syntax and build=%s is not supported: %s" % (module.params['build'], name))
+
         # Get package state.
         installed_state = get_package_state(name, pkg_spec, module)
 

From 59364500bc42014b9dd7f6edfec0ec05322abcc4 Mon Sep 17 00:00:00 2001
From: Patrik Lundin <patrik@sigterm.se>
Date: Thu, 30 Jun 2016 18:51:35 +0200
Subject: [PATCH 7/9] Improve debug logging some more.

---
 packaging/os/openbsd_pkg.py | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

diff --git a/packaging/os/openbsd_pkg.py b/packaging/os/openbsd_pkg.py
index de37a769b05..c5beab1d8aa 100644
--- a/packaging/os/openbsd_pkg.py
+++ b/packaging/os/openbsd_pkg.py
@@ -229,7 +229,7 @@ def package_latest(name, installed_state, pkg_spec, module):
             module.debug("package_latest(): checking for pre-upgrade package name: %s" % installed_name)
             match = re.search("\W%s->.+: ok\W" % installed_name, stdout)
             if match:
-                module.debug("package_latest(): package name match: %s" % installed_name)
+                module.debug("package_latest(): pre-upgrade package name match: %s" % installed_name)
                 if module.check_mode:
                     module.exit_json(changed=True)
 

From d55f22a2c6b0276b6e2e98b0fe441f68ffc88c04 Mon Sep 17 00:00:00 2001
From: Patrik Lundin <patrik@sigterm.se>
Date: Thu, 30 Jun 2016 18:55:43 +0200
Subject: [PATCH 8/9] Make fail messages all use lowercase messages.

---
 packaging/os/openbsd_pkg.py | 14 +++++++-------
 1 file changed, 7 insertions(+), 7 deletions(-)

diff --git a/packaging/os/openbsd_pkg.py b/packaging/os/openbsd_pkg.py
index c5beab1d8aa..cc7db96138e 100644
--- a/packaging/os/openbsd_pkg.py
+++ b/packaging/os/openbsd_pkg.py
@@ -299,7 +299,7 @@ def parse_package_name(name, pkg_spec, module):
     # Stop if someone is giving us a name that both has a version and is
     # version-less at the same time.
     if version_match and versionless_match:
-        module.fail_json(msg="Package name both has a version and is version-less: " + name)
+        module.fail_json(msg="package name both has a version and is version-less: " + name)
 
     # If name includes a version.
     if version_match:
@@ -312,7 +312,7 @@ def parse_package_name(name, pkg_spec, module):
             pkg_spec['flavor']            = match.group('flavor')
             pkg_spec['style']             = 'version'
         else:
-            module.fail_json(msg="Unable to parse package name at version_match: " + name)
+            module.fail_json(msg="unable to parse package name at version_match: " + name)
 
     # If name includes no version but is version-less ("--").
     elif versionless_match:
@@ -325,7 +325,7 @@ def parse_package_name(name, pkg_spec, module):
             pkg_spec['flavor']            = match.group('flavor')
             pkg_spec['style']             = 'versionless'
         else:
-            module.fail_json(msg="Unable to parse package name at versionless_match: " + name)
+            module.fail_json(msg="unable to parse package name at versionless_match: " + name)
 
     # If name includes no version, and is not version-less, it is all a stem.
     else:
@@ -338,7 +338,7 @@ def parse_package_name(name, pkg_spec, module):
             pkg_spec['flavor']            = None
             pkg_spec['style']             = 'stem'
         else:
-            module.fail_json(msg="Unable to parse package name at else: " + name)
+            module.fail_json(msg="unable to parse package name at else: " + name)
 
     # If the stem contains an "%" then it needs special treatment.
     branch_match = re.search("%", pkg_spec['stem'])
@@ -347,9 +347,9 @@ def parse_package_name(name, pkg_spec, module):
         branch_release = "6.0"
 
         if version_match or versionless_match:
-            module.fail_json(msg="Package name using 'branch' syntax also has a version or is version-less: " + name)
+            module.fail_json(msg="package name using 'branch' syntax also has a version or is version-less: " + name)
         if StrictVersion(platform.release()) < StrictVersion(branch_release):
-            module.fail_json(msg="Package name using 'branch' syntax requires at least OpenBSD %s: %s" % (branch_release, name))
+            module.fail_json(msg="package name using 'branch' syntax requires at least OpenBSD %s: %s" % (branch_release, name))
 
         pkg_spec['style'] = 'branch'
 
@@ -358,7 +358,7 @@ def parse_package_name(name, pkg_spec, module):
     if pkg_spec['flavor']:
         match = re.search("-$", pkg_spec['flavor'])
         if match:
-            module.fail_json(msg="Trailing dash in flavor: " + pkg_spec['flavor'])
+            module.fail_json(msg="trailing dash in flavor: " + pkg_spec['flavor'])
 
 # Function used for figuring out the port path.
 def get_package_source_path(name, pkg_spec, module):

From 1453d55c2307bc36d482ebc82e744cc0746ec5b8 Mon Sep 17 00:00:00 2001
From: Patrik Lundin <patrik@sigterm.se>
Date: Fri, 1 Jul 2016 18:38:19 +0200
Subject: [PATCH 9/9] Improve debug log some more.

---
 packaging/os/openbsd_pkg.py | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

diff --git a/packaging/os/openbsd_pkg.py b/packaging/os/openbsd_pkg.py
index cc7db96138e..59fdd35c26b 100644
--- a/packaging/os/openbsd_pkg.py
+++ b/packaging/os/openbsd_pkg.py
@@ -477,7 +477,7 @@ def main():
         parse_package_name('sqlports', pkg_spec, module)
         installed_state = get_package_state('sqlports', pkg_spec, module)
         if not installed_state:
-            module.debug("main(): installing sqlports")
+            module.debug("main(): installing 'sqlports' because build=%s" % module.params['build'])
             package_present('sqlports', installed_state, pkg_spec, module)
 
     if name == '*':
EOF
fi

sed -e 's/\(ttyC[^0].*getty.*\)on /\1off/' /etc/ttys | sudo tee /etc/ttys > /dev/null
