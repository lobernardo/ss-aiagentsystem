import scansoloLocale from '../scansolo.json';
import mergedLocale from '../index';

describe('scansolo i18n namespace', () => {
  it('exposes a SCANSOLO namespace with sidebar labels for every module', () => {
    expect(scansoloLocale.SCANSOLO).toBeDefined();
    expect(scansoloLocale.SCANSOLO.SIDEBAR).toEqual({
      GROUP_LABEL: 'ScanSolo',
      PIPELINE: 'Pipeline',
      AGENT: 'Agente de IA',
      KNOWLEDGE: 'Conhecimento',
      FOLLOWUPS: 'Follow-ups',
      PROPOSALS: 'Propostas',
      EXECUTIONS: 'Execuções e auditoria',
    });
  });

  it('is registered in the English locale index without clobbering the shared SIDEBAR namespace', () => {
    expect(mergedLocale.SCANSOLO).toEqual(scansoloLocale.SCANSOLO);
    // en/index.js merges locale chunks with a shallow object spread, so a
    // top-level "SIDEBAR" key here would silently wipe out the pre-existing
    // shared SIDEBAR namespace other modules rely on. Nesting our labels
    // under SCANSOLO.SIDEBAR instead avoids that collision.
    expect(scansoloLocale.SCANSOLO.SIDEBAR).not.toBe(mergedLocale.SIDEBAR);
    expect(mergedLocale.SIDEBAR.CAPTAIN).toBeDefined();
  });
});
