"""Bounded native weapon descriptions and owner-approved pickup requests."""
import re
from equipment import class_path,validate_construction,construction_lines
from snapshot import transform

ITEM_ID=re.compile(r'^drop(?:[1-9]|1[0-6])$')
def owner(value,zero=False):return type(value)is int and (0 if zero else 1)<=value<=9999999
def validate_items(items):
 if not isinstance(items,list)or len(items)>16:return False
 seen=set()
 for item in items:
  if (not isinstance(item,dict)or set(item)-{'construction'}!={'id','class','transform','grant'}
    or not isinstance(item['id'],str)or not ITEM_ID.fullmatch(item['id'])or item['id']in seen
    or not class_path(item['class'],'weapon')or not isinstance(item['transform'],list)
    or not transform(item['transform'])or not owner(item['grant'],True)
    or ('construction'in item and not validate_construction(item['construction']))):return False
  seen.add(item['id'])
 return True
def validate_requests(requests):
 if not isinstance(requests,list)or len(requests)>2:return False
 hands=set();items=set()
 for request in requests:
  if (not isinstance(request,dict)or set(request)!={'owner','id','hand'}or not owner(request['owner'])
    or not isinstance(request['id'],str)or not ITEM_ID.fullmatch(request['id'])
    or request['hand']not in ('right','left')or request['hand']in hands
    or(request['owner'],request['id'])in items):return False
  hands.add(request['hand']);items.add((request['owner'],request['id']))
 return True
def item_lines(items,requests):
 lines=[]
 for item in items:
  lines.append('|'.join(map(str,['DW',item['id'],item['class'],*item['transform'],item['grant']])))
  if 'construction'in item:lines.extend('D'+row for row in construction_lines(item['id'],item['construction']))
 lines.extend('|'.join(map(str,['DR',r['owner'],r['id'],r['hand']]))for r in requests)
 return lines
