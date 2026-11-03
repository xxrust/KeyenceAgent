"""Compare specific chunks between v3 and v3m to find what changed."""
import sqlite3

c3 = sqlite3.connect('H:/llm-wiki-v2-keyence/v3/wiki.v3.db')
c3m = sqlite3.connect('H:/llm-wiki-v2-keyence/v3/wiki.v3m.db')

# Check the chunks that should contain the missing answers
test_chunks = [
    ('03_32_FBFUN_Motion::chunk-038', 'MC_ChangeTargetPosition'),
    ('03_32_FBFUN_Motion::chunk-054', 'MC_TorqueLimitClutch'),
    ('03_16_FBFUN_CharacterProcessing::chunk-017', 'SplitN'),
]

for cid, keyword in test_chunks:
    r3 = c3.execute("select title, substr(text,1,400) from chunks where chunk_id=?", (cid,)).fetchone()
    r3m = c3m.execute("select extractor, title, substr(text,1,400) from chunks where chunk_id=?", (cid,)).fetchone()

    print(f"\n{'='*80}")
    print(f"Chunk: {cid} (looking for: {keyword})")
    print(f"{'='*80}")

    if r3:
        print(f"v3  title: {r3[0]}")
        print(f"v3  text: {r3[1][:250]}...")
        print()

    if r3m:
        print(f"v3m extractor: {r3m[0]}")
        print(f"v3m title: {r3m[1]}")
        print(f"v3m text: {r3m[2][:250]}...")
        print()

        if r3m[0] and r3m[0] != 'text':
            print(f"*** REPLACED with {r3m[0]}")
            v3_has = keyword.lower() in (r3[0] + r3[1]).lower() if r3 else False
            v3m_has = keyword.lower() in (r3m[1] + r3m[2]).lower()
            print(f"*** Keyword '{keyword}' present: v3={v3_has}, v3m={v3m_has}")
        else:
            print("*** NOT replaced (still using original text)")

# Count how many chunks were replaced
replaced = c3m.execute("select count(*) from chunks where extractor like 'mineru%'").fetchone()[0]
total = c3m.execute("select count(*) from chunks").fetchone()[0]
print(f"\n\nTotal chunks replaced with MinerU: {replaced} of {total} ({100*replaced/total:.1f}%)")
