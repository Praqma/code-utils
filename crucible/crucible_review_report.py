import re
import argparse
import requests
import json
from dotmap import DotMap


user='<user_name>' 
password='<password>' 

crucible_rest_base_url='<url>/rest-service/' #http_base_url
crucible_reviewsForIssue_extension_url='search-v1/reviewsForIssue?jiraKey='
crucible_review_interface_extension_url='reviews-v1/'

headers={'content-type':'application/json', 'accept':'application/json'}
auth=(user,password)

parser = argparse.ArgumentParser()
parser.add_argument("-f", \
                    "--pac_md_file", \
                    required=True, \
                    help="The markdown file produced by PAC tools" )
parser.add_argument("-d", \
                    "--debug", \
                    action='store_true', \
                    default='false', \
                    help="Print debug information" )
parser.add_argument("-a", \
                    "--listaccum", \
                    action='store_true', \
                    default='false', \
                    help="Also list the commits for Accumulated .... merges from ready2master. String match based" )

args = parser.parse_args()

pac_md_file=args.pac_md_file
debug=args.debug
listaccum=args.listaccum


review_ok=[]
review_review=[]
review_draft=[]
review_other=[]

def get_issue_ok_list_crucible(issue_id):
	reviewsForIssue  = crucible_rest_base_url
	reviewsForIssue += crucible_reviewsForIssue_extension_url
	reviewsForIssue += issue_id
#	print reviewsForIssue
	r = requests.get(reviewsForIssue, auth=auth, headers=headers)
	
	parsed_json = json.loads(r.text)

#	print json.dumps(parsed_json, sort_keys=True, indent=4)

	reviewData_list = parsed_json['reviewData']
	reviews=[]
	for reviewitem in reviewData_list:
		permaId = reviewitem['permaId']['id']
		reviews.append(permaId)


	for review in reviews:
		url_str  = crucible_rest_base_url 
		url_str += crucible_review_interface_extension_url
		url_str += review
		url_str += '/details'
		r = requests.get(url_str, auth=auth, headers=headers)
		parsed_json = json.loads(r.text)
	#	print json.dumps(parsed_json, sort_keys=True, indent=4)
		
		jsonmap = DotMap(parsed_json)
		review_status = jsonmap.state
		if review_status == 'Closed': 
			for revision, revision2 in jsonmap.reviewItems.items():
				string = revision2[0]['expandedRevisions'][0]['revision'][:7]
				review_ok.append(string)
		elif review_status == 'Review':
			for revision, revision2 in jsonmap.reviewItems.items():
				string = revision2[0]['expandedRevisions'][0]['revision'][:7]
				review_review.append(string)
		elif review_status == 'Draft' :
			for revision, revision2 in jsonmap.reviewItems.items():
				string = revision2[0]['expandedRevisions'][0]['revision'][:7]
				review_draft.append(string)
		else:
			for revision, revision2 in jsonmap.reviewItems.items():
				string = revision2[0]['expandedRevisions'][0]['revision'][:7]
				string += ':' + review_status
				review_other.append(string)
		

pac_issuenone_regex = re.compile('^## [Unspecified|Nones].*$')
pac_issueid_regex = re.compile('^##\s(SAM-\d+).*$')
pac_issueid_accum_regex = re.compile('^-\s([a-z0-9]{7}):\s(Accumulated commit of the following from branch.*$)')
pac_issueid_real_regex = re.compile('^-\s([a-z0-9]{7}):\s(.*$)')
pac_issueid_stats_regex = re.compile('^##\sStatistics')

with open(pac_md_file) as f:
	for line in f:
		m = pac_issueid_regex.match(line)
		if m: 
			get_issue_ok_list_crucible(m.group().replace('## ','').split(' ')[0])
			continue

#print review_ok
#print review_review
#print review_draft
#print review_other

with open(pac_md_file) as f:
	for line in f:
		m = pac_issueid_regex.match(line)
		if m: 
			print '\n'
			print m.group().replace('## ','').replace(' Unspecified','Unspecified').replace(' Nones', 'Nones')
#			Unspecified','Unspecified').replace(' Nones:)
#			get_issue(m.group().replace('##',''))
			continue

		m = pac_issueid_accum_regex.match(line) 
		if m:
			if listaccum == True: 
				print "( )Accum : " + m.group(1)[0:7] + " " + m.group(2)
			continue

		m = pac_issueid_real_regex.match(line) 
		if m:
			if m.group(1)[0:7] in review_ok:
				print " (+)Real  : " + m.group(1)[0:7] + " " + m.group(2)
			elif m.group(1)[0:7] in review_review:
				print " (r)Real  : " + m.group(1)[0:7] + " " + m.group(2)
			elif m.group(1)[0:7] in review_draft:
				print " (d)Real  : " + m.group(1)[0:7] + " " + m.group(2)
			else:
				print " ( )Real  : " + m.group(1)[0:7] + " " + m.group(2)
			continue

		pac_issueid_stats_regex
		m = pac_issuenone_regex.match(line)
		if m:
			print
			print (m.group().replace('## ', '') + ':')
			continue

if review_other:
	print "For some reason these reviews are in weird state, but refered:"  
	for review in review_other:
		print review