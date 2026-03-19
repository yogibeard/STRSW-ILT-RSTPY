# %% [markdown]
# #### The Header Comment Section
# 
# This section usually includes details such as 
# - the file name, 
# - author, 
# - date, 
# - purpose of the program, and any other relevant information. 
# 
# It’s a good practice to include such comments for better readability and maintainability of the code 

# %%
#! /usr/local/bin/python3

"""
ONTAP 9.13.1 REST API Python Client Library Scripts
Author: Vish Hulikal
This script performs the following:
        - Create a qtree (or quota tree)
        - Create a quota policy rule

usage: python3.11 qtree.py [-h] -c cluster -v VOLUME_NAME -vs VSERVER_NAME -q QTREE_NAME
       -sh SPACE_HARD -fh FILE_HARD [-u API_USER] [-p API_PASS]
The following arguments are required: -v/--volume_name, -vs/--vserver_name,
          -q/--qtree_name, -sh/--space_hard, -fh/--file_hard
"""


# %% [markdown]
# #### The Input Section:
# 
# Since we are using a Jupyter Notebook to run the code and not running the code from the command line, we need this section to simulate entering the arguments from the command line.
# 
# When you run the notebook, for example by clicking on the `Run All` button, a dialog prompt will appear at the top of the window. You will then need to enter the command line arguments as described in the usage section above.
# 
# If you do not provide the user, `admin`is used. If you do not provide the password, you will be prompted for the password.
# 
# Suggested command arguments:

# %%
#-c cluster1 -v Vol1 -vs nas_svm -q QTree1 -sh 100 -fh 1000

# %%
#import sys
#
## Prompt the user to enter command line arguments
#args = input("Please enter command line arguments: ")
#
## Split the entered string into a list of arguments
#args = args.split()
#
## Assign the list of arguments to sys.argv
#sys.argv = ['ipykernel_launcher.py'] + args
#
# %% [markdown]
# #### Import Section
# 
# Here we will import the following modules:
#   - [`argparse`](https://pypi.org/project/argparse/) : This is a popular python module. The argparse module makes it easy to write user friendly command line interfaces. 
#   The program defines what arguments it requires, and argparse will figure out how to parse those out of sys.argv. The argparse module also automatically generates help and usage messages and issues errors when users give the program invalid arguments.
#   - [`getpass`](https://docs.python.org/3/library/getpass.html) : Used to Prompt the user for a password without echoing
#   - [`logging`](https://pypi.org/project/logging/) : This module is intended to provide a standard error logging mechanism in Python as per PEP 282.
#   - [`netapp_ontap.config`](https://library.netapp.com/ecmdocs/ECMLP3319064/html/config.html) : This module contains the global configuration options and related functions for the library.
#   - [`netapp_ontap.host_connection`](https://library.netapp.com/ecmdocs/ECMLP3319064/html/host_connection.html) : This module defines a host connection object which is used to communicate with the API host
#   - [`netapp_ontap.error`](https://library.netapp.com/ecmdocs/ECMLP3319064/html/error.html) : This module defines the custom exception type. All exceptions raised by the library descend from this type
#   - [`netapp_ontap.resources.qtree`](https://library.netapp.com/ecmdocs/ECMLP2858435/html/resources/qtree.html) : A qtree is a logically defined file system that can exist as a special subdirectory of the root directory within a FlexVol or a FlexGroup volume
#   - [`netapp_ontap.resources.quota_rule`](https://library.netapp.com/ecmdocs/ECMLP2858435/html/resources/quota_rule.html) : Quotas are defined in quota rules specific to FlexVol volumes or FlexGroup volumes. Each quota rule has a type

# %%

import argparse
from getpass import getpass
import logging

from netapp_ontap import config, HostConnection, NetAppRestError
from netapp_ontap.resources import Qtree, QuotaRule


# %% [markdown]
# #### Function Definitions
# 
# There are 2 functions defined:
#   - `create_qtree`
#   - `create_policy_rule`

# %%

def create_qtree(volume_name: str, vserver_name: str, qtree_name: str) -> None:
    """Creates a new quota tree in a volume"""

    data = {
        'name': qtree_name,
        'volume': {'name': volume_name},
        'svm': {'name': vserver_name},
        'security_style': 'unix',
        'unix_permissions': 744,
        'export_policy_name': 'default',
#        'qos_policy': {'max_throughput_ops': 1000}
    }
    qtree = Qtree(**data)
    try:
        qtree.post()
        print("Qtree %s created successfully" % qtree.name)
    except NetAppRestError as err:
        print("Error: QTree was not created: %s" % err)
    return



# %%
def create_policy_rule(volume_name: str, vserver_name: str, qtree_name: str, space_hard: int, file_hard: int) -> None:
    """Creates a new policy rule for the qtree"""

    data = {
        'qtree': {'name': qtree_name},
        'volume': {'name': volume_name},
        'svm': {'name': vserver_name},
        'files': {'hard_limit': file_hard, 'soft_limit': 100},
        'space': {'hard_limit': space_hard, 'soft_limit': 100},
        'type': 'tree'
    }
    quotarule = QuotaRule(**data)
    try:
        quotarule.post()
        print("Rule 'tree' created successfully for %s" % qtree_name)
    except NetAppRestError as err:
        print("Error: Rule was not created: %s" % err)
    return



# %% [markdown]
# #### Arguments Parser
# 
# We define which arguments need to be passed to the script and argparse does the rest...

# %%
def parse_args() -> argparse.Namespace:
    """Parse the command line arguments from the user"""

    parser = argparse.ArgumentParser(
        description="This script will create a new qtree."
    )
    parser.add_argument(
        "-c", "--cluster", required=True, help="API server IP:port details"
    )
    parser.add_argument(
        "-v", "--volume_name", required=True, help="Volume name to create qtree from"
    )
    parser.add_argument(
        "-vs", "--vserver_name", required=True, help="SVM to create the volume from"
    )
    parser.add_argument(
        "-q", "--qtree_name", required=True, help="QTree to create the qutoa tree"
    )
    parser.add_argument(
        "-sh", "--space_hard", required=True, help="Hard limit on space in bytese"
    )
    parser.add_argument(
        "-fh", "--file_hard", required=True, help="hard limit on files in bytes"
    )
    parser.add_argument("-u", "--api_user", default="admin", help="API Username")
    parser.add_argument("-p", "--api_pass", help="API Password")
    parsed_args = parser.parse_args()

    # collect the password without echo if not already provided
    if not parsed_args.api_pass:
        parsed_args.api_pass = getpass()

    return parsed_args



# %% [markdown]
# #### The Main Section

# %%
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] [%(levelname)5s] [%(module)s:%(lineno)s] %(message)s",
    )
    args = parse_args()
    config.CONNECTION = HostConnection(
        args.cluster, username=args.api_user, password=args.api_pass, verify=False,
    )

    # Create a quota tree and a policy rule for the qtree
    create_qtree(args.volume_name, args.vserver_name, args.qtree_name)
    create_policy_rule(args.volume_name, args.vserver_name, args.qtree_name, args.space_hard, args.file_hard)


# %% [markdown]
# [Return to the Module 2 Notebook:](module2.ipynb)


