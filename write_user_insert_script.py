import argparse

parser = argparse.ArgumentParser(
    description="A small tool to read a csv of usernames and passwords, and output a shell script that can be run to insert said users into a samba server. Each line of the csv file should take the form 'username, password'"
)
parser.add_argument(
    '--infile', '-i', type=str, default='usernames_and_passwords.csv',
    help='The csv file to read the usernames and passwords from.'
)
parser.add_argument(
    '--outfile', '-o', type=str, default='custom.sh',
    help='The file to output the usernames and passwords to.'
)

args = parser.parse_args()

user_insert_script = open(args.outfile, 'w')
username_password_file = open(args.infile, 'r')

user_insert_script.write('#!/bin/bash\n')

for line in username_password_file:
    username, password = (entry.strip() for entry in line.split(','))
    user_insert_script.write(
        'samba-tool user add {0} {1}\n'.format(username, password)
    )
