<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license 
# if purchased from OpenC3, Inc.
-->

<template>
  <v-app :style="classificationStyles">
    <app-nav class="d-print-none" edition="COSMOS" />

    <!-- Sizes your content based upon application components -->
    <v-main>
      <v-container fluid>
        <div id="openc3-tool"></div>
        <div><router-view /></div>
      </v-container>
    </v-main>
    <app-footer app class="d-print-none" edition="COSMOS" license="AGPLv3" />
    <time-check />
  </v-app>
</template>

<script>
import AppFooter from '../../packages/openc3-tool-common/src/tools/base/AppFooter'
import AppNav from '../../packages/openc3-tool-common/src/tools/base/AppNav'
import TimeCheck from '../../packages/openc3-tool-common/src/tools/base/components/TimeCheck'
import ClassificationBanners from '../../packages/openc3-tool-common/src/tools/base/components/ClassificationBanners'
export default {
  components: {
    AppFooter,
    AppNav,
    TimeCheck,
  },
  mixins: [ClassificationBanners],
}
</script>
