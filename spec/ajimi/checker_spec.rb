require 'spec_helper'

describe Ajimi::Checker do
  let(:source) { Ajimi::Server.new }
  let(:target) { Ajimi::Server.new }
  let(:checker) { Ajimi::Checker.new(source, target, "/") }

  describe "#check" do
    let(:entry1) { make_entry("path1, mode1, user1, group1, bytes1") }
    let(:entry2) { make_entry("path2, mode2, user2, group2, bytes2") }
    let(:entry2_changed) { make_entry("path2, mode2, user2, group2, bytes2_changed") }

    context "when 2 servers have same entries" do
      it "returns true" do
        allow(source).to receive(:entries).and_return([entry1, entry2])
        allow(target).to receive(:entries).and_return([entry1, entry2])
        expect(checker.check).to be true
      end
    end

    context "when 2 servers have different entries" do
      it "returns false" do
        allow(source).to receive(:entries).and_return([entry1, entry2])
        allow(target).to receive(:entries).and_return([entry1, entry2_changed])
        expect(checker.check).to be false
      end

      it "returns diff position" do
        allow(source).to receive(:command_exec).and_return(<<-SOURCE_STDOUT
/root, dr-xr-x---, root, root, 4096
/root/.bash_history, -rw-------, root, root, 4847
/root/.bash_logout, -rw-r--r--, root, root, 18
/root/.bash_profile, -rw-r--r--, root, root, 176
/root/.bashrc, -rw-r--r--, root, root, 176
/root/.cshrc, -rw-r--r--, root, root, 100
        SOURCE_STDOUT
        )
        allow(target).to receive(:command_exec).and_return(<<-TARGET_STDOUT
/root, dr-xr-x---, root, root, 4096
/root/.bash_logout, -rw-r--r--, root, root, 18
/root/.bash_profile, -rw-r--r--, root, root, 176
/root/.bashrc, -rw-r--r--, root, root, 176
/root/.cshrc, -rw-r--r--, root, root, 100
/root/.ssh, drwx------, root, root, 4096
        TARGET_STDOUT
        )
        checker.check
        expect(checker.diffs.first.first.position).to be 1
        expect(checker.diffs.last.first.position).to be 5

      end
    end

  end

  let(:source_entry1) { make_entry("/root, dr-xr-x---, root, root, 4096") }
  let(:source_entry2) { make_entry("/root/.bash_history, -rw-------, root, root, 4847") }
  let(:source_entry3) { make_entry("/root/.bash_logout, -rw-r--r--, root, root, 18") }
  let(:source_entry4) { make_entry("/root/.ssh/authorized_keys, -rw-------, root, root, 1099") }

  let(:target_entry1) { make_entry("/root, dr-xr-x---, root, root, 4096") }
  let(:target_entry2) { make_entry("/root/.bash_history, -rw-------, root, root, 4847") }
  let(:target_entry3) { make_entry("/root/.bash_logout, -rw-r--r--, root, root, 18") }
  let(:target_entry3_changed) { make_entry("/root/.bash_logout, -rw-r--r--, root, root, 118") }

  describe "#raw_diff_entries" do

    let(:diffs) { checker.diff_entries(source_entries, target_entries) }

    context "when source and target have same entry" do
      let(:source_entries) { [source_entry1, source_entry2, source_entry3] }
      let(:target_entries) { [target_entry1, target_entry2, target_entry3] }

      it "has empty list" do
        expect(diffs.empty?).to be true
      end
    end
    
    context "when target has entry2" do
      let(:source_entries) { [source_entry1] }
      let(:target_entries) { [target_entry1, target_entry2] }

      it "has + entry" do
        expect(diffs.first.first.action).to eq "+"
        expect(diffs.first.first.element).to eq target_entry2
      end
    end

    context "when target does not have entry2" do
      let(:source_entries) { [source_entry1, source_entry2, source_entry3] }
      let(:target_entries) { [target_entry1, target_entry3] }

      it "has - entry" do
        expect(diffs.first.first.action).to eq "-"
        expect(diffs.first.first.element).to eq source_entry2
      end
    end

    context "when entry3 has changed" do
      let(:source_entries) { [source_entry1, source_entry3] }
      let(:target_entries) { [target_entry1, target_entry3_changed] }

      it "has - entry" do
        expect(diffs.first.first.action).to eq "-"
        expect(diffs.first.first.element).to eq source_entry3
      end
      it "has + entry" do
        expect(diffs.first.last.action).to eq "+"
        expect(diffs.first.last.element).to eq target_entry3_changed
      end

    end

  end

  describe "#diff_entries" do
    context "when ignore list is empty" do
      let(:source_entries) { [source_entry1] }
      let(:target_entries) { [target_entry1, target_entry2] }
      let(:ignore_list) { [] }
      let(:diffs) { checker.diff_entries(source_entries, target_entries, ignore_list) }

      it "has + entry" do
        expect(diffs.first.first.action).to eq "+"
        expect(diffs.first.first.element).to eq target_entry2
      end
    end

    context "when ignore list has strings" do
      let(:source_entries) { [source_entry1, source_entry3] }
      let(:target_entries) { [target_entry1, target_entry2, target_entry3_changed] }
      let(:ignore_list) { ["/hoge", "/root/.bash_logout"] }
      let(:diffs) { checker.diff_entries(source_entries, target_entries, ignore_list) }

      it "filters ignore_list" do
        expect(diffs.first.size).to eq 1
        expect(diffs.first.first.action).to eq "+"
        expect(diffs.first.first.element).to eq target_entry2
      end
    end

    context "when ignore list has regexp" do
      let(:source_entries) { [source_entry1, source_entry3, source_entry4] }
      let(:target_entries) { [target_entry1, target_entry2, target_entry3_changed] }
      let(:ignore_list) { [%r|\A/root/\.bash.*|] }
      let(:diffs) { checker.diff_entries(source_entries, target_entries, ignore_list) }

      it "filters ignore_list" do
        expect(diffs.first.size).to eq 1
        expect(diffs.first.first.action).to eq "-"
        expect(diffs.first.first.element).to eq source_entry4
      end
    end

    context "when ignore list has unknown type" do
      let(:source_entries) { [source_entry1, source_entry3, source_entry4] }
      let(:target_entries) { [target_entry1, target_entry2, target_entry3_changed] }
      let(:ignore_list) { [1, 2, 3] }

      it "raise_error TypeError" do
        expect{ checker.diff_entries(source_entries, target_entries, ignore_list) }.to raise_error(TypeError)
      end
    end

  end

end
