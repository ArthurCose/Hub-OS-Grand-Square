<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.8" tiledversion="1.8.2" name="bleachers" tilewidth="64" tileheight="64" tilecount="12" columns="6">
 <tileoffset x="0" y="16"/>
 <image source="bleachers.png" width="384" height="128"/>
 <tile id="0" type="Stairs">
  <properties>
   <property name="Direction" value="Up Right"/>
  </properties>
 </tile>
 <tile id="1" type="Stairs">
  <properties>
   <property name="Direction" value="Down Left"/>
  </properties>
 </tile>
 <tile id="2" type="Stairs">
  <properties>
   <property name="Direction" value="Up Right"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" x="15.8423" y="39.0399">
    <polygon points="-1.84228,1.96009 31.1577,-31.0399 31.1577,-39.0399 -15.8423,-39.0399 -15.8423,1.96009"/>
   </object>
  </objectgroup>
 </tile>
 <tile id="3" type="Stairs">
  <properties>
   <property name="Direction" value="Down Left"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="2" x="0" y="0" width="64" height="24"/>
  </objectgroup>
 </tile>
 <tile id="4" type="Stairs">
  <properties>
   <property name="Direction" value="Up Right"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" x="15" y="40">
    <polygon points="0,0 40,-40 49,-40 49,9 0,9"/>
   </object>
  </objectgroup>
 </tile>
 <tile id="5" type="Stairs">
  <properties>
   <property name="Direction" value="Down Left"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" x="0" y="25" width="64" height="39"/>
  </objectgroup>
 </tile>
 <tile id="7" type="Stairs"/>
</tileset>
