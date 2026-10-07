// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// MySQL Module
//

#include "amxxmodule.h"
#include "MysqlQuery.h"
#include "MysqlDatabase.h"
#include "MysqlResultSet.h"
#include <amtl/am-string.h>

using namespace SourceMod;

MysqlQuery::MysqlQuery(const char *querystring, MysqlDatabase *db) :
	m_pDatabase(db)
{
	m_QueryLen = strlen(querystring);
	m_QueryString = new char[m_QueryLen + 1];
	m_LastRes = NULL;
	strcpy(m_QueryString, querystring);
}

MysqlQuery::~MysqlQuery()
{
	if (m_LastRes)
	{
		m_LastRes->FreeHandle();
	}

	delete [] m_QueryString;
}

void MysqlQuery::FreeHandle()
{
	delete this;
}

bool MysqlQuery::Execute(QueryInfo *info, char *error, size_t maxlength)
{
	/* The last result set reads what is left of its results, before the next query is sent. */
	if (m_LastRes)
	{
		m_LastRes->FreeHandle();
		m_LastRes = NULL;
	}

	bool res = ExecuteR(info, error, maxlength);

	m_LastRes = (MysqlResultSet *)info->rs;

	return res;
}

bool MysqlQuery::Execute2(QueryInfo *info, char *error, size_t maxlength)
{
	if (m_LastRes)
	{
		m_LastRes->FreeHandle();
		m_LastRes = NULL;
	}

	bool res = ExecuteR(info, error, maxlength);

	m_LastRes = (MysqlResultSet *)info->rs;

	if (!info->success)
	{
		info->insert_id = 0;
	}

	return res;
}

const char *MysqlQuery::GetQueryString()
{
	return m_QueryString;
}

bool MysqlQuery::ExecuteR(QueryInfo *info, char *error, size_t maxlength)
{
	int err;

	if ( (err=mysql_real_query(m_pDatabase->m_pMysql, m_QueryString, (unsigned long)m_QueryLen)) )
	{
		info->errorcode = mysql_errno(m_pDatabase->m_pMysql);
		info->success = false;
		info->affected_rows = 0;
		info->rs = NULL;
		if (error && maxlength)
		{
			ke::SafeSprintf(error, maxlength, "%s", mysql_error(m_pDatabase->m_pMysql));
		}
	}
	else
	{
		MYSQL *mysql = m_pDatabase->m_pMysql;
		MYSQL_RES *res = mysql_store_result(mysql);

		info->errorcode = 0;
		info->success = true;
		info->affected_rows = mysql_affected_rows(mysql);
		info->insert_id = mysql_insert_id(mysql);
		info->rs = NULL;

		/**
		 * A statement without a result set may be followed by more (multiple statements):
		 * go on to the first result set, so it can be read and the connection stays in sync.
		 */
		while (!res && mysql_field_count(mysql) == 0 && mysql_more_results(mysql))
		{
			if (mysql_next_result(mysql) != 0)
			{
				break;
			}
			res = mysql_store_result(mysql);
		}

		if (res)
		{
			MysqlResultSet *rs = new MysqlResultSet(res, mysql);
			info->rs = rs;
		}
		else if (mysql_errno(mysql))
		{
			info->errorcode = mysql_errno(mysql);
			info->success = false;
			info->affected_rows = 0;
			if (error && maxlength)
			{
				ke::SafeSprintf(error, maxlength, "%s", mysql_error(mysql));
			}
		}
	}

	return info->success;
}

