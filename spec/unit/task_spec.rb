require 'thread'

RSpec.describe(Dry::Monads::Task) do
  result = Dry::Monads::Result
  success = result::Success.method(:new)
  failure = result::Failure.method(:new)

  maybe = Dry::Monads::Maybe
  some = maybe::Some.method(:new)

  task = described_class

  def task(&block)
    described_class.new(&block)
  end

  def deferred(&block)
    -> do
      expect(Thread.current).not_to be(Thread.main)
      block.call
    end
  end

  subject do
    task(&deferred { 1 })
  end

  describe '.new' do
    it 'delays the execution' do
      expect(subject.value!).to be 1
    end
  end

  describe '#fmap' do
    it 'chains transformations' do
      chain = subject.fmap { |v| v * 2 }

      expect(chain.value!).to be 2
    end

    it 'runs a block only on success' do
      called = false
      t = task { 1 / 0 }.fmap { called = true }
      t.to_result

      expect(called).to be(false)
    end
  end

  describe '#bind' do
    it 'combines computations' do
      chain = subject.bind { |v| task { v * 2 } }

      expect(chain.value!).to be 2
    end
  end

  describe '#to_result' do
    it 'transforms a successful execution to Result' do
      expect(subject.to_result).to eql(success[1])
    end

    it 'transforms an unsuccessful result to a Failure' do
      error = task { 1 / 0 }.to_result
      expect(error).to be_a_failure
      expect(error.failure).to be_a(ZeroDivisionError)
    end
  end

  describe '#to_maybe' do
    it 'transforms a successful execution to Some' do
      expect(subject.to_maybe).to eql(some[1])
    end

    it 'transforms an unsuccessful result to None' do
      error = task { 1 / 0 }.to_maybe
      expect(error).to be_none
    end
  end

  describe '#value!' do
    it 'unwraps the value' do
      expect(subject.value!).to be 1
    end

    it 'raises an error on unsuccessful computation' do
      expect { task { 1 / 0 }.value! }.to raise_error(Dry::Monads::UnwrapError)
    end
  end

  describe '#inspect' do
    it 'inspects pending' do
      t = task { sleep 0.01 }
      expect(t.inspect).to eql("Task(state=pending)")
    end

    it 'inspects resolved' do
      t = task { :something }.tap(&:value!)
      expect(t.inspect).to eql("Task(state=resolved value=:something)")
    end

    it 'inspects failed' do
      1 / 0 rescue err = $!
      t = task { raise err }.tap(&:to_result)
      expect(t.inspect).to eql("Task(state=rejected error=#{ err.inspect })")
    end
  end

  describe '#to_s' do
    it 'is an alias for inspect' do
      expect(subject.method(:to_s)).to eql(subject.method(:inspect))
    end
  end

  describe '#or' do
    it 'runs a block on failure' do
      m = task { 1 / 0 }.or { task { :success } }
      expect(m.wait).to eql(task { :success }.wait)
    end

    it 'ignores blocks on success' do
      m = subject.or { task { :success } }
      expect(m.wait).to eql(task { 1 }.wait)
    end
  end

  describe '#or_fmap' do
    it 'runs a block on failure' do
      m = task { 1 / 0 }.or_fmap { :success }.to_result
      expect(m).to eql(success[:success])
    end
  end

  describe '#value_or' do
    specify 'if success unwraps the value' do
      expect(subject.value_or { 2 }).to be(1)
    end

    specify 'if failure calls the given block' do
      expect(task { 1 / 0 }.value_or { 2 }).to be(2)
    end
  end

  describe '#complete?' do
    it 'checks whether the task is complete' do
      expect(task { sleep 0.01 }.wait).to be_complete
      expect(task { sleep 0.01 }).not_to be_complete
    end
  end

  describe '#wait' do
    it 'waits for resolution' do
      expect(task { sleep 0.01 }.wait).to be_complete
      expect(task { sleep 0.01 }).not_to be_complete
    end

    it 'accepts a timeout' do
      expect(task { sleep 10 }.wait(0.01)).not_to be_complete
    end
  end

  describe '.[]' do
    let(:io) { Concurrent::ImmediateExecutor.new }

    it 'allows to inject an underlying executor' do
      expect(task[io, &-> { Thread.current }].to_result).to eql(success[Thread.main])
    end
  end
end
