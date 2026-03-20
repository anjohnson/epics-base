/*************************************************************************\
* Copyright (c) 2007 UChicago Argonne LLC, as Operator of Argonne
*     National Laboratory.
* Copyright (c) 2002 The Regents of the University of California, as
*     Operator of Los Alamos National Laboratory.
* SPDX-License-Identifier: EPICS
* EPICS BASE is distributed subject to a Software License Agreement found
* in file LICENSE that is included with this distribution.
\*************************************************************************/

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "macLib.h"
#include "dbDefs.h"
#include "envDefs.h"
#include "errlog.h"
#include "epicsUnitTest.h"
#include "testMain.h"

MAC_HANDLE *h;

/* Callback helpers for testMacIterateMacros */
static long countCallback(void *user, const char *name, const char *value)
{
    (*(int*)user)++;
    return 0;
}

static char iterLastName[64];
static char iterLastValue[64];

static long captureLastCallback(void *user, const char *name, const char *value)
{
    (*(int*)user)++;
    strncpy(iterLastName,  name,  sizeof(iterLastName)-1);
    iterLastName[sizeof(iterLastName)-1]   = '\0';
    strncpy(iterLastValue, value, sizeof(iterLastValue)-1);
    iterLastValue[sizeof(iterLastValue)-1] = '\0';
    return 0;
}

static long earlyStopCallback(void *user, const char *name, const char *value)
{
    (*(int*)user)++;
    return 1; /* stop after first */
}

static void testMacIterateMacros(void)
{
    MAC_HANDLE *lh;
    MAC_HANDLE  badHandle;
    int n;
    long ret;

    if (macCreateHandle(&lh, NULL))
        testAbort("macCreateHandle() failed for iterate tests");
    macSuppressWarning(lh, TRUE);

    /* NULL handle */
    n = 0;
    testOk(macIterateMacros(NULL, countCallback, &n) == -1,
           "NULL handle: returns -1");

    /* Invalid magic */
    badHandle = *lh;
    badHandle.magic = 0;
    testOk(macIterateMacros(&badHandle, countCallback, &n) == -1,
           "invalid magic: returns -1");

    /* Empty handle */
    n = 0;
    ret = macIterateMacros(lh, countCallback, &n);
    testOk(n == 0 && ret == 0, "empty handle: count 0, returns 0");

    /* One macro */
    macPutValue(lh, "A", "hello");
    n = 0;
    macIterateMacros(lh, captureLastCallback, &n);
    testOk(n == 1, "one macro: count == 1");
    testOk(strcmp(iterLastName, "A") == 0 && strcmp(iterLastValue, "hello") == 0,
           "one macro: name==\"A\", value==\"hello\"");

    /* Two macros */
    macPutValue(lh, "B", "world");
    n = 0;
    macIterateMacros(lh, countCallback, &n);
    testOk(n == 2, "two macros: count == 2");

    /* Re-create handle for scope tests */
    macDeleteHandle(lh);
    if (macCreateHandle(&lh, NULL))
        testAbort("macCreateHandle() failed for scope tests");
    macSuppressWarning(lh, TRUE);

    /* pushScope alone: scope marker skipped */
    macPushScope(lh);
    n = 0;
    macIterateMacros(lh, countCallback, &n);
    testOk(n == 0, "pushScope only: scope marker skipped, count == 0");

    /* pushScope + two macros */
    macPutValue(lh, "C", "val1");
    macPutValue(lh, "D", "val2");
    n = 0;
    macIterateMacros(lh, countCallback, &n);
    testOk(n == 2, "pushScope + 2 macros: count == 2");

    /* Same name at two scope levels */
    macDeleteHandle(lh);
    if (macCreateHandle(&lh, NULL))
        testAbort("macCreateHandle() failed for shadow tests");
    macSuppressWarning(lh, TRUE);
    macPutValue(lh, "A", "outer");
    macPushScope(lh);
    macPutValue(lh, "A", "inner");
    n = 0;
    macIterateMacros(lh, captureLastCallback, &n);
    testOk(n == 1, "shadowed macro: count == 1");
    testOk(strcmp(iterLastValue, "inner") == 0,
           "shadowed macro: inner value reported");

    /* Early stop */
    macDeleteHandle(lh);
    if (macCreateHandle(&lh, NULL))
        testAbort("macCreateHandle() failed for early stop tests");
    macSuppressWarning(lh, TRUE);
    macPutValue(lh, "P", "1");
    macPutValue(lh, "Q", "2");
    macPutValue(lh, "R", "3");
    n = 0;
    macIterateMacros(lh, earlyStopCallback, &n);
    testOk(n == 1, "early stop: count == 1");

    /* visited flag reset: iterate twice on the same handle */
    n = 0;
    macIterateMacros(lh, countCallback, &n);
    testOk(n == 3, "visited reset: 1st iterate count == 3");
    n = 0;
    macIterateMacros(lh, countCallback, &n);
    testOk(n == 3, "visited reset: 2nd iterate count == 3");

    /* Expanded value */
    macDeleteHandle(lh);
    if (macCreateHandle(&lh, NULL))
        testAbort("macCreateHandle() failed for expand tests");
    macSuppressWarning(lh, TRUE);
    macPutValue(lh, "X", "hello");
    macPutValue(lh, "Y", "$(X) world");
    n = 0;
    iterLastValue[0] = '\0';
    macIterateMacros(lh, captureLastCallback, &n);
    testOk(strcmp(iterLastValue, "hello world") == 0,
           "expanded value: Y == \"hello world\"");

    /* Expansion failure: rawval reported, not empty */
    macDeleteHandle(lh);
    if (macCreateHandle(&lh, NULL))
        testAbort("macCreateHandle() failed for error tests");
    macSuppressWarning(lh, TRUE);
    macPutValue(lh, "Z", "$(UNDEF)");
    n = 0;
    iterLastValue[0] = '\0';
    macIterateMacros(lh, captureLastCallback, &n);
    testOk(n == 1 && iterLastValue[0] != '\0',
           "expansion failure: rawval reported (non-empty)");

    macDeleteHandle(lh);
}

static void check(const char *str, const char *expect)
{
    char output[MAC_SIZE] = {'\0'};
    long status = macExpandString(h, str, output, MAC_SIZE);
    long expect_len = strlen(expect+1);
    int expect_error = (expect[0] == '!');
    int statBad = expect_error ^ (status < 0);
    int strBad = strcmp(output, expect+1);

    testOk(!statBad && !strBad, "%s => %s", str, output);

    if (strBad) {
        testDiag("Got \"%s\", expected \"%s\"", output, expect+1);
    }
    if (statBad) {
        testDiag("Return status was %ld, expected %ld",
                 status, expect_error ? -expect_len : expect_len);
    }
}

static void ovcheck(void)
{
    char output[54];
    long status;

    macPutValue(h, "OVVAR","abcdefghijklmnopqrstuvwxyz");

    memset(output, '~', sizeof output);
    status = macExpandString(h, "abcdefghijklmnopqrstuvwxyz$(OVVAR)", output, 52);
    testOk(status == 51, "expansion returned %ld, expected 51", status);
    testOk(output[50] == 'y', "final character %x, expect 79 (y)", output[50]);
    testOk(output[51] == '\0', "terminator character %x, expect 0", output[51]);
    testOk(output[52] == '~', "sentinel character %x, expect 7e, (~)", output[52]);

    memset(output, '~', sizeof output);
    status = macExpandString(h, "abcdefghijklmnopqrstuvwxyz$(OVVAR)", output, 53);
    testOk(status == 52, "expansion returned %ld, expected 52", status);
    testOk(output[51] == 'z', "final character %x, expect 7a (z)", output[51]);
    testOk(output[52] == '\0', "terminator character %x, expect 0", output[52]);
    testOk(output[53] == '~', "sentinel character %x, expect 7e, (~)", output[53]);
}

MAIN(macLibTest)
{
    testPlan(108);

    if (macCreateHandle(&h, NULL))
        testAbort("macCreateHandle() failed");
    eltc(0);

    check("FOO", " FOO");

    check("$(FOO)", "!$(FOO,undefined)");
    check("${FOO}", "!$(FOO,undefined)");
    check("${FOO=${FOO}}", "!$(FOO,undefined)");
    check("${FOO,FOO}", "!$(FOO,undefined)");
    check("${FOO,FOO=${FOO}}", "!$(FOO,recursive)");
    check("${FOO,BAR}", "!$(FOO,undefined)");
    check("${FOO,BAR=baz}", "!$(FOO,undefined)");
    check("${FOO,BAR=${FOO}}", "!$(FOO,undefined)");
    check("${FOO,BAR=baz,FUM}", "!$(FOO,undefined)");
    check("${FOO=${BAR},BAR=${FOO}}", "!$(FOO,undefined)");
    check("${FOO,FOO=${BAR},BAR=${FOO}}", "!$(BAR,recursive)");

    check("${=}", " ");
    check("x${=}y", " xy");

    check("${,=}", " ");
    check("x${,=}y", " xy");

    check("${FOO=}", " ");
    check("x${FOO=}y", " xy");

    check("${FOO=,}", " ");
    check("x${FOO=,}y", " xy");

    check("${FOO,FOO=}", " ");
    check("x${FOO,FOO=}y", " xy");

    check("${FOO=,BAR}", " ");
    check("x${FOO=,BAR}y", " xy");

    check("${FOO=${BAR=}}", " ");
    check("x${FOO=${BAR=}}y", " xy");

    check("${FOO=,BAR=baz}", " ");
    check("x${FOO=,BAR=baz}y", " xy");

    check("${FOO=${BAR},BAR=}", " ");
    check("x${FOO=${BAR},BAR=}y", " xy");

    check("${=BAR}", " BAR");
    check("x${=BAR}y", " xBARy");

    check("${FOO=BAR}", " BAR");
    check("x${FOO=BAR}y", " xBARy");

    macPutValue(h, "FOO", "BLETCH");
        /* FOO = "BLETCH" */
    check("${FOO}", " BLETCH");
    check("${FOO,FOO}", " BLETCH");
    check("x${FOO}y", " xBLETCHy");
    check("x${FOO}y${FOO}z", " xBLETCHyBLETCHz");
    check("${FOO=BAR}", " BLETCH");
    check("x${FOO=BAR}y", " xBLETCHy");
    check("${FOO=${BAZ}}", " BLETCH");
    check("${FOO=${BAZ},BAR=${BAZ}}", " BLETCH");
    check("x${FOO=${BAZ}}y", " xBLETCHy");
    check("x${FOO=${BAZ},BAR=${BAZ}}y", " xBLETCHy");
    check("${BAR=${FOO}}", " BLETCH");
    check("x${BAR=${FOO}}y", " xBLETCHy");
    check("w${BAR=x${FOO}y}z", " wxBLETCHyz");

    check("${FOO,FOO=BAR}", " BAR");
    check("x${FOO,FOO=BAR}y", " xBARy");
    check("${BAR,BAR=${FOO}}", " BLETCH");
    check("x${BAR,BAR=${FOO}}y", " xBLETCHy");
    check("${BAR,BAR=${${FOO}},BLETCH=GRIBBLE}", " GRIBBLE");
    check("x${BAR,BAR=${${FOO}},BLETCH=GRIBBLE}y", " xGRIBBLEy");
    check("${${BAR,BAR=${FOO}},BLETCH=GRIBBLE}", " GRIBBLE");
    check("x${${BAR,BAR=${FOO}},BLETCH=GRIBBLE}y", " xGRIBBLEy");
    check("${N=${FOO}/${BAR},BAR=GLEEP}", " BLETCH/GLEEP");

    macPutValue(h, "BAR","GLEEP");
        /* FOO = "BLETCH" */
        /* BAR = "GLEEP" */
    check("${FOO}/${BAR}", " BLETCH/GLEEP");
    check("x${FOO}/${BAR}y", " xBLETCH/GLEEPy");
    check("${FOO,BAR}/${BAR}", " BLETCH/GLEEP");
    check("${FOO,BAR=x}/${BAR}", " BLETCH/GLEEP");
    check("${BAZ=BLETCH,BAR}/${BAR}", " BLETCH/GLEEP");
    check("${BAZ=BLETCH,BAR=x}/${BAR}", " BLETCH/GLEEP");
    check("${N=${FOO}/${BAR}}", " BLETCH/GLEEP");

    macPutValue(h, "BLETCH","BAR");
        /* FOO = "BLETCH" */
        /* BLETCH = "BAR" */
    check("${${FOO}}", " BAR");
    check("x${${FOO}}y", " xBARy");
    check("${${FOO}=GRIBBLE}", " BAR");
    check("x${${FOO}=GRIBBLE}y", " xBARy");

    macPutValue(h, "BLETCH","${BAR}");
        /* FOO = "BLETCH" */
        /* BLETCH = "${BAR}" */
        /* BAR = "GLEEP" */
    check("${${FOO}}", " GLEEP");
    check("${BLETCH=${FOO}}", " GLEEP");

    macPutValue(h, "FOO","${BAR}");
        /* FOO = "${BAR}" */
        /* BAR = "GLEEP" */
    check("${FOO}", " GLEEP");
    check("${FOO=BLETCH,BAR=BAZ}", " BAZ");

    macPutValue(h, "BAR","${BAZ}");
        /* FOO = "${BAR}" */
        /* BAR = "${BAZ}" */
    check("${FOO}", "!$(BAZ,undefined)");

    macPutValue(h, "BAR","${BAZ=GRIBBLE}");
        /* FOO = "${BAR}" */
        /* BAR = "${BAZ=GRIBBLE}" */
    check("${FOO}", " GRIBBLE");
    check("${FOO,BAZ=GEEK}", " GEEK");

    macPutValue(h, "BAR","${STR1}");
    macPutValue(h, "STR1","VAL1");
    macPutValue(h, "STR2","VAL2");
        /* FOO = "${BAR}" */
        /* BAR = "${STR1}" */
        /* STR1 = "VAL1" */
        /* STR2 = "VAL2" */
    check("${FOO}", " VAL1");

    macPutValue(h, "BAR","${STR2}");
        /* FOO = "${BAR}" */
        /* BAR = "${STR2}" */
        /* STR1 = "VAL1" */
        /* STR2 = "VAL2" */
    check("${FOO}", " VAL2");

    check("$(FOO)$(FOO1)", "!VAL2$(FOO1,undefined)");
    check("$(FOO1)$(FOO)", "!$(FOO1,undefined)VAL2");

    macPutValue(h, "BAR","${FOO}");
        /* FOO = "${BAR}" */
        /* BAR = "${FOO}" */
    check("${FOO}", "!$(BAR,recursive)");
    check("${FOO=GRIBBLE}", "!$(BAR,recursive)");
    check("${FOO=GRIBBLE,BAR=${FOO}}", "!$(BAR,recursive)");
    check("${FOO,FOO=${FOO}}", "!$(FOO,recursive)");
    check("${FOO=GRIBBLE,FOO=${FOO}}", "!$(FOO,recursive)");

    macSuppressWarning(h, TRUE);
    check("$(CRUX)", "!$(CRUX)");
    check("${FOO}", "!$(BAR)");

    ovcheck();

    testMacIterateMacros();

    return testDone();
}
