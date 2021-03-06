-- Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--      http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

CREATE TABLE session (
  last_session_no   integer unsigned NOT NULL default '0'
);
CREATE TABLE session_record (
  session_record_id integer NOT NULL primary key,
  session_id        integer unsigned NOT NULL default '0',
  type_id           integer unsigned NOT NULL default '0',
  code              varchar NOT NULL default '',
  data              text NOT NULL,
  created_at        timestamp NOT NULL default '0000-00-00 00:00:00',
  modified_at       timestamp NOT NULL default '0000-00-00 00:00:00'
);
CREATE TABLE type (
  type_id integer NOT NULL primary key ,
  code varchar(64) NOT NULL default ''
);
CREATE UNIQUE INDEX code on type (code);
CREATE UNIQUE INDEX session_id on session_record (session_id,type_id,code);
