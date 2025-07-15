#!/bin/bash
#                                             _      
#                                            | |     
#  __ _ _   _  __ _  ___ __ _ _ __ ___   ___ | | ___ 
# / _` | | | |/ _` |/ __/ _` | '_ ` _ \ / _ \| |/ _ \
#| (_| | |_| | (_| | (_| (_| | | | | | | (_) | |  __/
# \__, |\__,_|\__,_|\___\__,_|_| |_| |_|\___/|_|\___|
#  __/ |                                             
# |___/                                              
#	guacamole docker Raphael Jäger 15.07.2025

set -euo pipefail
# Check if whiptail is installed
if ! command -v whiptail >/dev/null 2>&1; then
    echo "Installing whiptail..."
    apt update && apt install -y whiptail
fi

# Install mysql-client (needed for connectivity check and SQL execution)
apt update && apt install -y mysql-client

# Check if docker network 'produktiv' exists
if ! docker network ls --format '{{.Name}}' | grep -q '^produktiv$'; then
    whiptail --title "Docker Network Missing" \
        --msgbox "The 'produktiv' network does not exist.\n\nIt seems you did not use the shQuick install script for Docker installation.\nPlease create the 'produktiv' network manually." 12 60
    exit 1
fi

# Prompt for MySQL connection details
MYSQL_HOSTNAME=$(whiptail --inputbox "Enter MySQL Server Hostname or IP:" 8 60 --title "MySQL Hostname" 3>&1 1>&2 2>&3)
MYSQL_DATABASE=$(whiptail --inputbox "Enter MySQL Database Name:" 8 60 --title "MySQL Database" 3>&1 1>&2 2>&3)
MYSQL_USER=$(whiptail --inputbox "Enter MySQL Username:" 8 60 --title "MySQL User" 3>&1 1>&2 2>&3)
MYSQL_PASSWORD=$(whiptail --passwordbox "Enter MySQL Password:" 8 60 --title "MySQL Password" 3>&1 1>&2 2>&3)
MYSQL_PORT=$(whiptail --inputbox "Enter MySQL Port:" 8 60 "3306" --title "MySQL Port" 3>&1 1>&2 2>&3)

# Validate database name (simple pattern)
if [[ ! "$MYSQL_DATABASE" =~ ^[a-zA-Z0-9_]+$ ]]; then
    whiptail --title "Invalid Database Name" \
        --msgbox "The database name is invalid.\nOnly letters, numbers, and underscores are allowed." 10 60
    exit 1
fi

# Test MySQL connection
if ! mysqladmin ping -h "$MYSQL_HOSTNAME" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent; then
    whiptail --title "MySQL Connection Failed" \
        --msgbox "Unable to connect to the MySQL server with the provided credentials.\n\nAborting installation." 10 60
    exit 1
fi

GUACD_HOSTNAME="guacd"

# Create volume only if it doesn't exist
if ! docker volume ls --format '{{.Name}}' | grep -q '^guacamole$'; then
    docker volume create guacamole
fi

# Create guacd container
docker run -d \
    --name guacd \
    --hostname "$GUACD_HOSTNAME" \
    --network produktiv \
    --restart always \
    guacamole/guacd

# Create guacamole container
docker run -d \
    --name guacamole \
    --hostname guacamole \
    --network produktiv \
    -v guacamole:/guacamole \
    -e MYSQL_HOSTNAME="$MYSQL_HOSTNAME" \
    -e MYSQL_DATABASE="$MYSQL_DATABASE" \
    -e MYSQL_USER="$MYSQL_USER" \
    -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    -e MYSQL_PORT="$MYSQL_PORT" \
    -e GUACD_HOSTNAME="guacd" \
    --restart always \
    guacamole/guacamole

# Execute SQL schema and admin user creation
mysql -h "$MYSQL_HOSTNAME" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" <<EOF
CREATE TABLE `guacamole_connection_group` (

  `connection_group_id`   int(11)      NOT NULL AUTO_INCREMENT,
  `parent_id`             int(11),
  `connection_group_name` varchar(128) NOT NULL,
  `type`                  enum('ORGANIZATIONAL',
                               'BALANCING') NOT NULL DEFAULT 'ORGANIZATIONAL',

  `max_connections`          int(11),
  `max_connections_per_user` int(11),
  `enable_session_affinity`  boolean NOT NULL DEFAULT 0,

  PRIMARY KEY (`connection_group_id`),
  UNIQUE KEY `connection_group_name_parent` (`connection_group_name`, `parent_id`),

  CONSTRAINT `guacamole_connection_group_ibfk_1`
    FOREIGN KEY (`parent_id`)
    REFERENCES `guacamole_connection_group` (`connection_group_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_connection` (

  `connection_id`       int(11)      NOT NULL AUTO_INCREMENT,
  `connection_name`     varchar(128) NOT NULL,
  `parent_id`           int(11),
  `protocol`            varchar(32)  NOT NULL,
  
  `proxy_port`              integer,
  `proxy_hostname`          varchar(512),
  `proxy_encryption_method` enum('NONE', 'SSL'),

  `max_connections`          int(11),
  `max_connections_per_user` int(11),
  
  `connection_weight`        int(11),
  `failover_only`            boolean NOT NULL DEFAULT 0,

  PRIMARY KEY (`connection_id`),
  UNIQUE KEY `connection_name_parent` (`connection_name`, `parent_id`),

  CONSTRAINT `guacamole_connection_ibfk_1`
    FOREIGN KEY (`parent_id`)
    REFERENCES `guacamole_connection_group` (`connection_group_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_entity` (

  `entity_id`     int(11)            NOT NULL AUTO_INCREMENT,
  `name`          varchar(128)       NOT NULL,
  `type`          enum('USER',
                       'USER_GROUP') NOT NULL,

  PRIMARY KEY (`entity_id`),
  UNIQUE KEY `guacamole_entity_name_scope` (`type`, `name`)

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_user` (

  `user_id`       int(11)      NOT NULL AUTO_INCREMENT,
  `entity_id`     int(11)      NOT NULL,

  `password_hash` binary(32)   NOT NULL,
  `password_salt` binary(32),
  `password_date` datetime     NOT NULL,

  `disabled`      boolean      NOT NULL DEFAULT 0,
  `expired`       boolean      NOT NULL DEFAULT 0,

  `access_window_start`    TIME,
  `access_window_end`      TIME,

  `valid_from`  DATE,
  `valid_until` DATE,

  `timezone` VARCHAR(64),

  `full_name`           VARCHAR(256),
  `email_address`       VARCHAR(256),
  `organization`        VARCHAR(256),
  `organizational_role` VARCHAR(256),

  PRIMARY KEY (`user_id`),

  UNIQUE KEY `guacamole_user_single_entity` (`entity_id`),

  CONSTRAINT `guacamole_user_entity`
    FOREIGN KEY (`entity_id`)
    REFERENCES `guacamole_entity` (`entity_id`)
    ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_user_group` (

  `user_group_id` int(11)      NOT NULL AUTO_INCREMENT,
  `entity_id`     int(11)      NOT NULL,

  `disabled`      boolean      NOT NULL DEFAULT 0,

  PRIMARY KEY (`user_group_id`),

  UNIQUE KEY `guacamole_user_group_single_entity` (`entity_id`),

  CONSTRAINT `guacamole_user_group_entity`
    FOREIGN KEY (`entity_id`)
    REFERENCES `guacamole_entity` (`entity_id`)
    ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_user_group_member` (

  `user_group_id`    int(11)     NOT NULL,
  `member_entity_id` int(11)     NOT NULL,

  PRIMARY KEY (`user_group_id`, `member_entity_id`),

  CONSTRAINT `guacamole_user_group_member_parent_id`
    FOREIGN KEY (`user_group_id`)
    REFERENCES `guacamole_user_group` (`user_group_id`) ON DELETE CASCADE,

  CONSTRAINT `guacamole_user_group_member_entity_id`
    FOREIGN KEY (`member_entity_id`)
    REFERENCES `guacamole_entity` (`entity_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE guacamole_sharing_profile (

  `sharing_profile_id`    int(11)      NOT NULL AUTO_INCREMENT,
  `sharing_profile_name`  varchar(128) NOT NULL,
  `primary_connection_id` int(11)      NOT NULL,

  PRIMARY KEY (`sharing_profile_id`),
  UNIQUE KEY `sharing_profile_name_primary` (sharing_profile_name, primary_connection_id),

  CONSTRAINT `guacamole_sharing_profile_ibfk_1`
    FOREIGN KEY (`primary_connection_id`)
    REFERENCES `guacamole_connection` (`connection_id`)
    ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_connection_parameter` (

  `connection_id`   int(11)       NOT NULL,
  `parameter_name`  varchar(128)  NOT NULL,
  `parameter_value` varchar(4096) NOT NULL,

  PRIMARY KEY (`connection_id`,`parameter_name`),

  CONSTRAINT `guacamole_connection_parameter_ibfk_1`
    FOREIGN KEY (`connection_id`)
    REFERENCES `guacamole_connection` (`connection_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE guacamole_sharing_profile_parameter (

  `sharing_profile_id` integer       NOT NULL,
  `parameter_name`     varchar(128)  NOT NULL,
  `parameter_value`    varchar(4096) NOT NULL,

  PRIMARY KEY (`sharing_profile_id`, `parameter_name`),

  CONSTRAINT `guacamole_sharing_profile_parameter_ibfk_1`
    FOREIGN KEY (`sharing_profile_id`)
    REFERENCES `guacamole_sharing_profile` (`sharing_profile_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE guacamole_user_attribute (

  `user_id`         int(11)       NOT NULL,
  `attribute_name`  varchar(128)  NOT NULL,
  `attribute_value` varchar(4096) NOT NULL,

  PRIMARY KEY (user_id, attribute_name),
  KEY `user_id` (`user_id`),

  CONSTRAINT guacamole_user_attribute_ibfk_1
    FOREIGN KEY (user_id)
    REFERENCES guacamole_user (user_id) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE guacamole_user_group_attribute (

  `user_group_id`   int(11)       NOT NULL,
  `attribute_name`  varchar(128)  NOT NULL,
  `attribute_value` varchar(4096) NOT NULL,

  PRIMARY KEY (`user_group_id`, `attribute_name`),
  KEY `user_group_id` (`user_group_id`),

  CONSTRAINT `guacamole_user_group_attribute_ibfk_1`
    FOREIGN KEY (`user_group_id`)
    REFERENCES `guacamole_user_group` (`user_group_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE guacamole_connection_attribute (

  `connection_id`   int(11)       NOT NULL,
  `attribute_name`  varchar(128)  NOT NULL,
  `attribute_value` varchar(4096) NOT NULL,

  PRIMARY KEY (connection_id, attribute_name),
  KEY `connection_id` (`connection_id`),

  CONSTRAINT guacamole_connection_attribute_ibfk_1
    FOREIGN KEY (connection_id)
    REFERENCES guacamole_connection (connection_id) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE guacamole_connection_group_attribute (

  `connection_group_id` int(11)       NOT NULL,
  `attribute_name`      varchar(128)  NOT NULL,
  `attribute_value`     varchar(4096) NOT NULL,

  PRIMARY KEY (connection_group_id, attribute_name),
  KEY `connection_group_id` (`connection_group_id`),

  CONSTRAINT guacamole_connection_group_attribute_ibfk_1
    FOREIGN KEY (connection_group_id)
    REFERENCES guacamole_connection_group (connection_group_id) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE guacamole_sharing_profile_attribute (

  `sharing_profile_id` int(11)       NOT NULL,
  `attribute_name`     varchar(128)  NOT NULL,
  `attribute_value`    varchar(4096) NOT NULL,

  PRIMARY KEY (sharing_profile_id, attribute_name),
  KEY `sharing_profile_id` (`sharing_profile_id`),

  CONSTRAINT guacamole_sharing_profile_attribute_ibfk_1
    FOREIGN KEY (sharing_profile_id)
    REFERENCES guacamole_sharing_profile (sharing_profile_id) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_connection_permission` (

  `entity_id`     int(11) NOT NULL,
  `connection_id` int(11) NOT NULL,
  `permission`    enum('READ',
                       'UPDATE',
                       'DELETE',
                       'ADMINISTER') NOT NULL,

  PRIMARY KEY (`entity_id`,`connection_id`,`permission`),

  CONSTRAINT `guacamole_connection_permission_ibfk_1`
    FOREIGN KEY (`connection_id`)
    REFERENCES `guacamole_connection` (`connection_id`) ON DELETE CASCADE,

  CONSTRAINT `guacamole_connection_permission_entity`
    FOREIGN KEY (`entity_id`)
    REFERENCES `guacamole_entity` (`entity_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_connection_group_permission` (

  `entity_id`           int(11) NOT NULL,
  `connection_group_id` int(11) NOT NULL,
  `permission`          enum('READ',
                             'UPDATE',
                             'DELETE',
                             'ADMINISTER') NOT NULL,

  PRIMARY KEY (`entity_id`,`connection_group_id`,`permission`),

  CONSTRAINT `guacamole_connection_group_permission_ibfk_1`
    FOREIGN KEY (`connection_group_id`)
    REFERENCES `guacamole_connection_group` (`connection_group_id`) ON DELETE CASCADE,

  CONSTRAINT `guacamole_connection_group_permission_entity`
    FOREIGN KEY (`entity_id`)
    REFERENCES `guacamole_entity` (`entity_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE guacamole_sharing_profile_permission (

  `entity_id`          integer NOT NULL,
  `sharing_profile_id` integer NOT NULL,
  `permission`         enum('READ',
                            'UPDATE',
                            'DELETE',
                            'ADMINISTER') NOT NULL,

  PRIMARY KEY (`entity_id`, `sharing_profile_id`, `permission`),

  CONSTRAINT `guacamole_sharing_profile_permission_ibfk_1`
    FOREIGN KEY (`sharing_profile_id`)
    REFERENCES `guacamole_sharing_profile` (`sharing_profile_id`) ON DELETE CASCADE,

  CONSTRAINT `guacamole_sharing_profile_permission_entity`
    FOREIGN KEY (`entity_id`)
    REFERENCES `guacamole_entity` (`entity_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_system_permission` (

  `entity_id`  int(11) NOT NULL,
  `permission` enum('CREATE_CONNECTION',
                    'CREATE_CONNECTION_GROUP',
                    'CREATE_SHARING_PROFILE',
                    'CREATE_USER',
                    'CREATE_USER_GROUP',
                    'AUDIT',
                    'ADMINISTER') NOT NULL,

  PRIMARY KEY (`entity_id`,`permission`),

  CONSTRAINT `guacamole_system_permission_entity`
    FOREIGN KEY (`entity_id`)
    REFERENCES `guacamole_entity` (`entity_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_user_permission` (

  `entity_id`        int(11) NOT NULL,
  `affected_user_id` int(11) NOT NULL,
  `permission`       enum('READ',
                          'UPDATE',
                          'DELETE',
                          'ADMINISTER') NOT NULL,

  PRIMARY KEY (`entity_id`,`affected_user_id`,`permission`),

  CONSTRAINT `guacamole_user_permission_ibfk_1`
    FOREIGN KEY (`affected_user_id`)
    REFERENCES `guacamole_user` (`user_id`) ON DELETE CASCADE,

  CONSTRAINT `guacamole_user_permission_entity`
    FOREIGN KEY (`entity_id`)
    REFERENCES `guacamole_entity` (`entity_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_user_group_permission` (

  `entity_id`              int(11) NOT NULL,
  `affected_user_group_id` int(11) NOT NULL,
  `permission`             enum('READ',
                                'UPDATE',
                                'DELETE',
                                'ADMINISTER') NOT NULL,

  PRIMARY KEY (`entity_id`, `affected_user_group_id`, `permission`),

  CONSTRAINT `guacamole_user_group_permission_affected_user_group`
    FOREIGN KEY (`affected_user_group_id`)
    REFERENCES `guacamole_user_group` (`user_group_id`) ON DELETE CASCADE,

  CONSTRAINT `guacamole_user_group_permission_entity`
    FOREIGN KEY (`entity_id`)
    REFERENCES `guacamole_entity` (`entity_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `guacamole_connection_history` (

  `history_id`           int(11)      NOT NULL AUTO_INCREMENT,
  `user_id`              int(11)      DEFAULT NULL,
  `username`             varchar(128) NOT NULL,
  `remote_host`          varchar(256) DEFAULT NULL,
  `connection_id`        int(11)      DEFAULT NULL,
  `connection_name`      varchar(128) NOT NULL,
  `sharing_profile_id`   int(11)      DEFAULT NULL,
  `sharing_profile_name` varchar(128) DEFAULT NULL,
  `start_date`           datetime     NOT NULL,
  `end_date`             datetime     DEFAULT NULL,

  PRIMARY KEY (`history_id`),
  KEY `user_id` (`user_id`),
  KEY `connection_id` (`connection_id`),
  KEY `sharing_profile_id` (`sharing_profile_id`),
  KEY `start_date` (`start_date`),
  KEY `end_date` (`end_date`),
  KEY `connection_start_date` (`connection_id`, `start_date`),

  CONSTRAINT `guacamole_connection_history_ibfk_1`
    FOREIGN KEY (`user_id`)
    REFERENCES `guacamole_user` (`user_id`) ON DELETE SET NULL,

  CONSTRAINT `guacamole_connection_history_ibfk_2`
    FOREIGN KEY (`connection_id`)
    REFERENCES `guacamole_connection` (`connection_id`) ON DELETE SET NULL,

  CONSTRAINT `guacamole_connection_history_ibfk_3`
    FOREIGN KEY (`sharing_profile_id`)
    REFERENCES `guacamole_sharing_profile` (`sharing_profile_id`) ON DELETE SET NULL

) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE guacamole_user_history (

  `history_id`           int(11)      NOT NULL AUTO_INCREMENT,
  `user_id`              int(11)      DEFAULT NULL,
  `username`             varchar(128) NOT NULL,
  `remote_host`          varchar(256) DEFAULT NULL,
  `start_date`           datetime     NOT NULL,
  `end_date`             datetime     DEFAULT NULL,

  PRIMARY KEY (history_id),
  KEY `user_id` (`user_id`),
  KEY `start_date` (`start_date`),
  KEY `end_date` (`end_date`),
  KEY `user_start_date` (`user_id`, `start_date`),

  CONSTRAINT guacamole_user_history_ibfk_1
    FOREIGN KEY (user_id)
    REFERENCES guacamole_user (user_id) ON DELETE SET NULL

) ENGINE=InnoDB DEFAULT CHARSET=utf8;


CREATE TABLE guacamole_user_password_history (

  `password_history_id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id`             int(11) NOT NULL,

  `password_hash` binary(32) NOT NULL,
  `password_salt` binary(32),
  `password_date` datetime   NOT NULL,

  PRIMARY KEY (`password_history_id`),
  KEY `user_id` (`user_id`),

  CONSTRAINT `guacamole_user_password_history_ibfk_1`
    FOREIGN KEY (`user_id`)
    REFERENCES `guacamole_user` (`user_id`) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8;


EOF

mysql -h "$MYSQL_HOSTNAME" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" <<EOF
INSERT INTO guacamole_entity (name, type) VALUES ('guacadmin', 'USER');
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
SELECT
    entity_id,
    x'CA458A7D494E3BE824F5E1E175A1556C0F8EEF2C2D7DF3633BEC4A29C4411960',  -- 'guacadmin'
    x'FE24ADC5E11E2B25288D1704ABE67A79E342ECC26064CE69C5B3177795A82264',
    NOW()
FROM guacamole_entity WHERE name = 'guacadmin';
INSERT INTO guacamole_system_permission (entity_id, permission)
SELECT entity_id, permission
FROM (
          SELECT 'guacadmin'  AS username, 'CREATE_CONNECTION'       AS permission
    UNION SELECT 'guacadmin'  AS username, 'CREATE_CONNECTION_GROUP' AS permission
    UNION SELECT 'guacadmin'  AS username, 'CREATE_SHARING_PROFILE'  AS permission
    UNION SELECT 'guacadmin'  AS username, 'CREATE_USER'             AS permission
    UNION SELECT 'guacadmin'  AS username, 'CREATE_USER_GROUP'       AS permission
    UNION SELECT 'guacadmin'  AS username, 'ADMINISTER'              AS permission
) permissions
JOIN guacamole_entity ON permissions.username = guacamole_entity.name AND guacamole_entity.type = 'USER';

INSERT INTO guacamole_user_permission (entity_id, affected_user_id, permission)
SELECT guacamole_entity.entity_id, guacamole_user.user_id, permission
FROM (
          SELECT 'guacadmin' AS username, 'guacadmin' AS affected_username, 'READ'       AS permission
    UNION SELECT 'guacadmin' AS username, 'guacadmin' AS affected_username, 'UPDATE'     AS permission
    UNION SELECT 'guacadmin' AS username, 'guacadmin' AS affected_username, 'ADMINISTER' AS permission
) permissions
JOIN guacamole_entity          ON permissions.username = guacamole_entity.name AND guacamole_entity.type = 'USER'
JOIN guacamole_entity affected ON permissions.affected_username = affected.name AND guacamole_entity.type = 'USER'
JOIN guacamole_user            ON guacamole_user.entity_id = affected.entity_id;

EOF

# Cleanup: remove mysql-client again
apt purge -y mysql-client && apt autoremove -y

# Final success message
whiptail --title "Installation Complete" \
    --msgbox "Guacamole and guacd containers have been successfully deployed!\n\nThe required MySQL schema and admin user have been set up.\n\nYou can now access Guacamole via your configured reverse proxy or hostname." 12 60
